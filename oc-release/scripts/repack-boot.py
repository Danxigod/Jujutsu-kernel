#!/usr/bin/env python3
"""repack-boot.py - sustituye el kernel de un boot.img de MTK conservando el resto.

El boot.img de este Redmi 9C tiene esta disposicion (verificada en el movil):

    offset 0        cabecera ANDROID! (kernel_size@8, ramdisk_size@16, page_size@36)
    offset 2048     kernel (gzip)
    offset 13.8 MB  ramdisk (gzip)
    + padding       bloque MTK de 64 bytes con el magic 0x1eabb7d7
                    + device tree (FDT) del fabricante

Modo normal (por defecto): el kernel nuevo se escribe en su hueco y se rellena
con ceros hasta el mismo tamaño, de modo que NI LA CABECERA NI EL RAMDISK NI EL
DTB cambian de sitio byte a byte.  Es la opcion mas segura.

Modo --shift: reconstruye la imagen con el tamano de kernel nuevo (solo si el
kernel nuevo no cabe en el hueco original).

Uso:
    repack-boot.py <stock.img> <kernel.gz|Image|Image.gz> <salida.img> [--shift]
    repack-boot.py --inspect <imagen.img>
"""

import argparse
import gzip
import struct
import sys
import zlib

BOOT_MAGIC = b"ANDROID!"
MTK_DTB_MAGIC = 0x1EABB7D7
MTK_DTB_HEADER_SIZE = 64
FDT_MAGIC = b"\xd0\x0d\xfe\xed"
ARM64_IMAGE_MAGIC = b"ARM\x64"


def align_up(value, alignment):
    return (value + alignment - 1) // alignment * alignment


class BootImage:
    def __init__(self, data):
        if data[:8] != BOOT_MAGIC:
            raise SystemExit("No es un boot.img de Android (magic %r)" % data[:8])
        self.data = bytearray(data)
        self.kernel_size = struct.unpack_from("<I", data, 8)[0]
        self.ramdisk_size = struct.unpack_from("<I", data, 16)[0]
        self.page_size = struct.unpack_from("<I", data, 36)[0]
        if self.page_size not in (2048, 4096, 16384):
            raise SystemExit("page_size inesperado: %d" % self.page_size)
        self.kernel_off = self.page_size
        self.ramdisk_off = align_up(self.kernel_off + self.kernel_size, self.page_size)
        self.dtb_tag_off = self.data.find(struct.pack("<I", MTK_DTB_MAGIC))
        self.fdt_off = None
        self.fdt_size = 0
        if self.dtb_tag_off >= 0:
            candidate = self.dtb_tag_off + MTK_DTB_HEADER_SIZE
            if bytes(self.data[candidate:candidate + 4]) == FDT_MAGIC:
                self.fdt_off = candidate
                self.fdt_size = struct.unpack_from(">I", self.data, candidate + 4)[0]

    def describe(self):
        lines = [
            "boot.img: %d bytes" % len(self.data),
            "  page_size      : %d" % self.page_size,
            "  kernel_size    : %d (offset %d -> %d)"
            % (self.kernel_size, self.kernel_off, self.kernel_off + self.kernel_size),
            "  ramdisk_size   : %d (offset %d -> %d)"
            % (self.ramdisk_size, self.ramdisk_off, self.ramdisk_off + self.ramdisk_size),
        ]
        if self.fdt_off is not None:
            lines.append(
                "  DTB OEM        : offset %d, %d bytes (magic MTK en %d)"
                % (self.fdt_off, self.fdt_size, self.dtb_tag_off)
            )
        else:
            lines.append("  DTB OEM        : no encontrado")
        return "\n".join(lines)

    def kernel_slot(self):
        """Bytes libres en el hueco del kernel antes del ramdisk."""
        return self.ramdisk_off - self.kernel_off


def load_kernel(path):
    raw = open(path, "rb").read()
    if raw[:2] == b"\x1f\x8b":
        return raw, "gzip (tal cual)"
    if raw[:4] == ARM64_IMAGE_MAGIC:
        return gzip.compress(raw, 9), "Image crudo -> recomprimido con gzip -9"
    raise SystemExit(
        "%s no es ni un .gz ni una Image ARM64 (magic %r)" % (path, raw[:4])
    )


def build_preserving(stock, kernel):
    out = bytearray(stock.data)
    slot = stock.kernel_slot()
    if len(kernel) > slot:
        raise SystemExit(
            "El kernel nuevo (%d bytes) no cabe en el hueco original (%d bytes).\n"
            "Usa --shift para reconstruir la imagen, o comprime mas el kernel."
            % (len(kernel), slot)
        )
    out[stock.kernel_off:stock.kernel_off + len(kernel)] = kernel
    out[stock.kernel_off + len(kernel):stock.ramdisk_off] = b"\x00" * (
        slot - len(kernel)
    )
    return out


def build_shifted(stock, kernel):
    ramdisk = bytes(stock.data[stock.ramdisk_off:stock.ramdisk_off + stock.ramdisk_size])
    if stock.fdt_off is not None:
        tag = bytes(stock.data[stock.dtb_tag_off:stock.fdt_off + stock.fdt_size])
    else:
        tag = b""

    out = bytearray(stock.data[: stock.page_size])
    struct.pack_into("<I", out, 8, len(kernel))

    out += kernel
    out += b"\x00" * (align_up(len(out), stock.page_size) - len(out))
    out += ramdisk
    out += b"\x00" * (align_up(len(out), stock.page_size) - len(out))
    out += tag
    out += b"\x00" * (align_up(len(out), stock.page_size) - len(out))
    out += b"\x00" * max(0, len(stock.data) - len(out))
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inspect", metavar="IMG", help="muestra la estructura y sale")
    parser.add_argument("--shift", action="store_true", help="reconstruye moviendo ramdisk/DTB")
    parser.add_argument("stock", nargs="?", help="boot.img original")
    parser.add_argument("kernel", nargs="?", help="Image.gz / Image a empaquetar")
    parser.add_argument("out", nargs="?", help="boot.img de salida")
    args = parser.parse_args()

    if args.inspect:
        stock = BootImage(open(args.inspect, "rb").read())
        print(stock.describe())
        return 0

    if not (args.stock and args.kernel and args.out):
        parser.error("faltan argumentos (usa --help)")

    stock = BootImage(open(args.stock, "rb").read())
    print(stock.describe())
    kernel, kind = load_kernel(args.kernel)
    print("  kernel nuevo   : %s, %d bytes" % (kind, len(kernel)))

    out = build_shifted(stock, kernel) if args.shift else build_preserving(stock, kernel)

    check = BootImage(bytes(out))
    if check.ramdisk_size != stock.ramdisk_size:
        raise SystemExit("fallo interno: el ramdisk cambio de tamano")
    if stock.fdt_off is not None:
        if check.fdt_off is None or check.fdt_size != stock.fdt_size:
            raise SystemExit("fallo interno: el DTB del OEM no se conserva")
        if bytes(out[check.fdt_off:check.fdt_off + check.fdt_size]) != bytes(
            stock.data[stock.fdt_off:stock.fdt_off + stock.fdt_size]
        ):
            raise SystemExit("fallo interno: el DTB cambio de contenido")

    open(args.out, "wb").write(out)
    print("  -> %s (%d bytes)" % (args.out, len(out)))
    print("  El ramdisk y el DTB del OEM se conservan intactos.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

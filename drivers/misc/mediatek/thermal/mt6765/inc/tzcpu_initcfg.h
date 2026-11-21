/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Copyright (C) 2019 MediaTek Inc.
 * Copyright (C) 2021 XiaoMi, Inc.
 */

#ifndef __TZCPU_INITCFG_H__
#define __TZCPU_INITCFG_H__

#define TZCPU_SET_INIT_CFG			(1)

#define TZCPU_INITCFG_INTERVAL			(200)
#define TZCPU_INITCFG_NUM_TRIPS			(2)

/*
 * Thermal unlock profile (external cooler on the back cover):
 * TRIP_0 stays at the hardware protection point (117 C) - that one is a
 * hardware trip and cannot be moved. Every software trip is pushed 20 C up
 * so the CPU keeps boosting instead of dropping to the throttle bins.
 */
#define TZCPU_INITCFG_TRIP_0_TEMP		(117000)
#define TZCPU_INITCFG_TRIP_0_COOLER		"mtktscpu-sysrst"

#define TZCPU_INITCFG_TRIP_1_TEMP		(90000)
#define TZCPU_INITCFG_TRIP_1_COOLER		"cpu_adaptive_0"

#define TZCPU_INITCFG_TRIP_2_TEMP		(89000)
#define TZCPU_INITCFG_TRIP_2_COOLER		""

#define TZCPU_INITCFG_TRIP_3_TEMP		(88000)
#define TZCPU_INITCFG_TRIP_3_COOLER		""

#define TZCPU_INITCFG_TRIP_4_TEMP		(87000)
#define TZCPU_INITCFG_TRIP_4_COOLER		""

#define TZCPU_INITCFG_TRIP_5_TEMP		(85000)
#define TZCPU_INITCFG_TRIP_5_COOLER		""

#define TZCPU_INITCFG_TRIP_6_TEMP		(80000)
#define TZCPU_INITCFG_TRIP_6_COOLER		""

#define TZCPU_INITCFG_TRIP_7_TEMP		(75000)
#define TZCPU_INITCFG_TRIP_7_COOLER		""

#define TZCPU_INITCFG_TRIP_8_TEMP		(70000)
#define TZCPU_INITCFG_TRIP_8_COOLER		""

#define TZCPU_INITCFG_TRIP_9_TEMP		(65000)
#define TZCPU_INITCFG_TRIP_9_COOLER		""


#endif	/* __TZCPU_INITCFG_H__ */



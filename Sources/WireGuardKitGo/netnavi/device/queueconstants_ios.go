//go:build ios

/* SPDX-License-Identifier: MIT
 *
 * Copyright (C) 2017-2023 WireGuard LLC. All Rights Reserved.
 */

package device

// Fit within memory limits for iOS's Network Extension API, which has stricter requirements.
// These are vars instead of consts, because heavier network extensions might want to reduce
// them further.
var (
    // down by deviding 4
	QueueStagedSize                   = 128/4
	QueueOutboundSize                 = 1024/4
	QueueInboundSize                  = 1024/4
	QueueHandshakeSize                = 1024/4
	PreallocatedBuffersPerPool uint32 = 1024/4
)

const MaxSegmentSize = 1700

export const ErrorCode = {
  AUTH_FAILED: 4001,
  DEVICE_NOT_PAIRED: 4002,
  PAIR_CODE_INVALID: 4003,
  TARGET_OFFLINE: 4004,
  SESSION_NOT_FOUND: 4005,
  COMMAND_BLOCKED: 4006,
} as const

export type ErrorCode = (typeof ErrorCode)[keyof typeof ErrorCode]

export const ErrorMessage: Record<ErrorCode, string> = {
  [ErrorCode.AUTH_FAILED]: '认证失败',
  [ErrorCode.DEVICE_NOT_PAIRED]: '设备未配对',
  [ErrorCode.PAIR_CODE_INVALID]: '配对码无效或已过期',
  [ErrorCode.TARGET_OFFLINE]: '目标设备离线',
  [ErrorCode.SESSION_NOT_FOUND]: '会话不存在',
  [ErrorCode.COMMAND_BLOCKED]: '指令被安全策略拦截',
}

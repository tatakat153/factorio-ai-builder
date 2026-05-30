/** 急停 (Executor) */
import { post } from "../lib/bridge.js";
export const name = "factorio_emergency_stop";
export const description = "紧急停止！立即取消所有正在执行的操作（行走、挖掘、建造、手搓）。角色停止一切活动。恢复需调用 factorio_emergency_reset。";
export const parameters = { type: "object", properties: {}, required: [] };
export async function execute(input, ctx) {
  const data = await post(ctx, "/api/v1/emergency-stop");
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

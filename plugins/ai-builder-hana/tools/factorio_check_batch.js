/** 查询批量进度 (Executor) */
import { get } from "../lib/bridge.js";
export const name = "factorio_check_batch";
export const description = "查询批量建造的进度和状态。返回 state(building/paused_obstacle/paused_missing/completed/cancelled)、进度、障碍列表、缺失物品。";
export const parameters = { type: "object", properties: { batch_id: { type: "string" } }, required: ["batch_id"] };
export async function execute(input, ctx) {
  const data = await get(ctx, `/api/v1/agent/build/batch/${input.batch_id}`);
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

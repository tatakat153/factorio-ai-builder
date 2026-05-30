/** 删除标记 (Planner) — AI 主动清理缓存 */
import { del } from "../lib/bridge.js";
export const name = "factorio_unmark_area";
export const description = "删除区域标记，释放缓存。AI 应在不再需要某个区域的信息时主动调用此工具清理。";
export const parameters = { type: "object", properties: { mark_id: { type: "string" } }, required: ["mark_id"] };
export async function execute(input, ctx) {
  const data = await del(ctx, `/api/v1/world/mark/${input.mark_id}`);
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

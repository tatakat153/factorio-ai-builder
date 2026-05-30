/** 列出所有标记 (Planner) */
import { get } from "../lib/bridge.js";
export const name = "factorio_list_marks";
export const description = "列出当前所有区域标记。用于检查哪些区域已被标记、是否需要清理过期标记。";
export const parameters = { type: "object", properties: {}, required: [] };
export async function execute(input, ctx) {
  const data = await get(ctx, "/api/v1/world/marks");
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

/** 查询科技 (Planner) */
import { get } from "../lib/bridge.js";
export const name = "factorio_get_technologies";
export const description = "查询科技树。参数 only_available=true 时只返回可研究但尚未完成的科技。返回科技名称、前置、所需科技包、是否已研究。";
export const parameters = { type: "object", properties: { only_available: { type: "boolean", default: true } }, required: [] };
export async function execute(input, ctx) {
  const data = await get(ctx, `/api/v1/technologies?only_available=${input.only_available !== false}`);
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

/** 查询圈地详情 (Planner) — 压缩后的实体列表 */
import { get } from "../lib/bridge.js";
export const name = "factorio_get_area_detail";
export const description = "获取已标记区域的详细压缩数据。相同配方的机器会合并，传送带会折叠为路径段。返回 compressed_entity_count 和 raw_entity_count 可对比压缩效果。";
export const parameters = { type: "object", properties: { mark_id: { type: "string" } }, required: ["mark_id"] };
export async function execute(input, ctx) {
  const data = await get(ctx, `/api/v1/world/mark/${input.mark_id}`);
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

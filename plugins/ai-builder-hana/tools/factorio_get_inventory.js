/** 查询背包 (Planner) */
import { get } from "../lib/bridge.js";
export const name = "factorio_get_inventory";
export const description = "查询 AI 角色的完整背包内容。返回物品名称和数量。用于判断是否有足够材料建造/手搓。";
export const parameters = { type: "object", properties: {}, required: [] };
export async function execute(input, ctx) {
  const data = await get(ctx, "/api/v1/agent/inventory");
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

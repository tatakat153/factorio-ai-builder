/** 查询可用配方 (Planner) */
import { get } from "../lib/bridge.js";
export const name = "factorio_get_recipes";
export const description = "查询当前科技解锁的所有可用配方。返回配方名称、输入材料、输出产品、制作类别。用于规划建造方案时确认配方可行性。";
export const parameters = { type: "object", properties: {}, required: [] };
export async function execute(input, ctx) {
  const data = await get(ctx, "/api/v1/recipes");
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

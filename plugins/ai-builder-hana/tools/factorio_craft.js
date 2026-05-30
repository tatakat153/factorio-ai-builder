/** 手搓 (Planner) */
import { post } from "../lib/bridge.js";
export const name = "factorio_craft";
export const description = "让 AI 角色手搓物品。需要角色背包中有足够原料。返回实际排队的数量。";
export const parameters = { type: "object", properties: { recipe_name: { type: "string" }, count: { type: "number", default: 1 } }, required: ["recipe_name"] };
export async function execute(input, ctx) {
  const data = await post(ctx, "/api/v1/agent/craft", { recipe_name: input.recipe_name, count: input.count || 1 });
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

/** 设置配方 (Executor) */
import { post } from "../lib/bridge.js";
export const name = "factorio_set_recipe";
export const description = "为机器（组装机、熔炉等）设置配方。机器必须已被放置在指定位置。";
export const parameters = {
  type: "object",
  properties: { entity_name: { type: "string" }, x: { type: "number" }, y: { type: "number" }, recipe_name: { type: "string" } },
  required: ["entity_name", "x", "y", "recipe_name"],
};
export async function execute(input, ctx) {
  const data = await post(ctx, "/api/v1/agent/recipe", { entity_name: input.entity_name, position: { x: input.x, y: input.y }, recipe_name: input.recipe_name });
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

/** 开始研究 (Planner) */
import { post } from "../lib/bridge.js";
export const name = "factorio_start_research";
export const description = "开始研究指定科技。研究会自动消耗科技包。";
export const parameters = { type: "object", properties: { technology_name: { type: "string" } }, required: ["technology_name"] };
export async function execute(input, ctx) {
  const data = await post(ctx, "/api/v1/research/enqueue", { technology_name: input.technology_name });
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

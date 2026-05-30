/** 查询角色状态 (Planner + Executor) */
import { get } from "../lib/bridge.js";
export const name = "factorio_get_agent_state";
export const description = "查询 AI 角色的当前状态：位置、血量、是否忙、当前动作、背包摘要、急停状态。Planner 用于判断是否需要移动，Executor 用于判断行走是否到达。";
export const parameters = { type: "object", properties: {}, required: [] };
export async function execute(input, ctx) {
  const data = await get(ctx, "/api/v1/agent/state");
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

/** 行走 (Executor) */
import { post, get } from "../lib/bridge.js";
export const name = "factorio_walk_to";
export const description = `控制 AI 角色走到指定坐标。使用游戏内置寻路，自动避开障碍物。
调用后应立即用 factorio_get_agent_state 轮询，直到 agent 到达或卡住。

参数：
- x, y: 目标坐标
- strict_goal: 是否严格要求到达精确位置（默认 false）`;

export const parameters = {
  type: "object",
  properties: {
    x: { type: "number" },
    y: { type: "number" },
    strict_goal: { type: "boolean", default: false },
  },
  required: ["x", "y"],
};

export async function execute(input, ctx) {
  const data = await post(ctx, "/api/v1/agent/walk", {
    goal: { x: input.x, y: input.y },
    strict_goal: input.strict_goal || false,
  });

  if (data.queued) {
    // Poll until done (with a timeout)
    let status;
    for (let i = 0; i < 120; i++) {
      await new Promise(r => setTimeout(r, 500));
      status = await get(ctx, "/api/v1/agent/walk/status");
      if (status.state === "arrived" || status.state === "stuck") break;
    }

    return {
      content: [{
        type: "text",
        text: JSON.stringify({
          state: status?.state || "unknown",
          position: status?.position,
          stuck_position: status?.stuck_position,
          waypoints_remaining: status?.waypoints_remaining,
        }, null, 2),
      }],
    };
  }

  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

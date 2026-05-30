/**
 * 接近目标 (Executor)
 * 走到目标附近的"可触及距离"，而非目标精确坐标。
 * 用于采矿/建造前的移动：不会走到障碍物里面去。
 */
import { post } from "../lib/bridge.js";

export const name = "factorio_approach_to";
export const description = `走到目标坐标附近的"可触及距离"（默认 9 格），而非目标的精确坐标。
使用场景：采矿或放置实体前，不应走到资源/实体的精确坐标上（那会导致徘徊），
而应走到刚好能挖掘/建造的距离。

参数：
- x, y: 目标坐标
- distance: 接近距离（默认 9 = build_distance - 1）`;

export const parameters = {
  type: "object",
  properties: {
    x: { type: "number", description: "目标 X 坐标" },
    y: { type: "number", description: "目标 Y 坐标" },
    distance: { type: "number", description: "接近距离（默认 9）" },
  },
  required: ["x", "y"],
};

export async function execute(input, ctx) {
  const data = await post(ctx, "/api/v1/agent/walk/approach", {
    goal: { x: input.x, y: input.y },
  });

  if (data.queued) {
    let status;
    for (let i = 0; i < 120; i++) {
      await new Promise(r => setTimeout(r, 500));
      status = await (await fetch(`${(await import("../lib/bridge.js")).getBridgeUrl(ctx)}/api/v1/agent/walk/status`)).json();
      if (status.state === "arrived" || status.state === "stuck") break;
    }

    return {
      content: [{
        type: "text",
        text: JSON.stringify({
          state: status?.state || "unknown",
          position: status?.position,
          stuck_obstacle: status?.stuck_obstacle,
        }, null, 2),
      }],
    };
  }

  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

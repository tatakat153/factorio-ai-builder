/**
 * 连接桥接服务，获取健康状态
 * Planner + Executor
 */
import { get } from "../lib/bridge.js";

export const name = "factorio_connect";
export const description = "检查与 Factorio 桥接服务的连接状态。在发送任何其他命令之前应先调用此工具。";

export const parameters = { type: "object", properties: {}, required: [] };

export async function execute(input, ctx) {
  try {
    const data = await get(ctx, "/api/v1/health");
    return {
      content: [{
        type: "text",
        text: JSON.stringify(data, null, 2),
      }],
    };
  } catch (err) {
    return {
      content: [{
        type: "text",
        text: `连接失败: ${err.message}\n\n请确认:\n1. Factorio 以 Multiplayer 模式运行\n2. RCON 已启用 (config.ini: local-rcon-socket=127.0.0.1:34198)\n3. 桥接服务已启动 (python bridge/main.py)`,
      }],
    };
  }
}

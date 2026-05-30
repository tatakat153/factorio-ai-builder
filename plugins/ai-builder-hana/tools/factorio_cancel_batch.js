/** 取消批量 (Executor) */
import { post } from "../lib/bridge.js";
export const name = "factorio_cancel_batch";
export const description = "取消正在进行的批量建造。";
export const parameters = { type: "object", properties: { batch_id: { type: "string" } }, required: ["batch_id"] };
export async function execute(input, ctx) {
  const data = await post(ctx, `/api/v1/agent/build/batch/${input.batch_id}/cancel`);
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

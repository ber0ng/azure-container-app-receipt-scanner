import { PatchOperation } from "@azure/cosmos";
import { ServiceBusReceivedMessage, ServiceBusReceiver } from "@azure/service-bus";
import { config } from "./config";
import { blobContainer, receipts, serviceBus } from "./clients";
import { extractor } from "./extractor";
import { ReceiptMessage, ReceiptStatus } from "./types";

async function updateReceipt(id: string, status: ReceiptStatus, extra: { result?: unknown; error?: string } = {}) {
    const ops: PatchOperation[] = [
        { op: "set", path: "/status", value: status },
        { op: "set", path: "/updatedAt", value: new Date().toISOString() },
    ];
    if (extra.result !== undefined) ops.push({ op: "set", path: "/result", value: extra.result });
    if (extra.error !== undefined) ops.push({ op: "set", path: "/error", value: extra.error });
    await receipts.item(id, id).patch(ops);
}

async function handle(receiver: ServiceBusReceiver, msg: ServiceBusReceivedMessage) {
    const body = msg.body as Partial<ReceiptMessage>;
    if (!body?.receiptId || !body?.blobName) {
        // Poison message: retrying won't help.
        await receiver.deadLetterMessage(msg, {
            deadLetterReason: "InvalidBody",
            deadLetterErrorDescription: "Missing receiptId or blobName",
        });
        return;
    }
    const { receiptId, blobName } = body;

    try {
        console.log(`Processing ${receiptId} (attempt ${msg.deliveryCount})`);
        await updateReceipt(receiptId, "processing");
        const document = await blobContainer.getBlobClient(blobName).downloadToBuffer();
        const result = await extractor.extract(document);
        await updateReceipt(receiptId, "completed", { result });
        await receiver.completeMessage(msg);
        console.log(`Completed ${receiptId}`);
    } catch (err) {
        const error = err instanceof Error ? err.message : String(err);
        console.error(`Failed ${receiptId}: ${error}`);
        if ((msg.deliveryCount ?? 1) >= config.maxAttempts) {
            await updateReceipt(receiptId, "failed", { error }).catch(() => undefined);
            await receiver.deadLetterMessage(msg, { deadLetterReason: "ProcessingFailed", deadLetterErrorDescription: error });
        } else {
            await receiver.abandonMessage(msg); // back on the queue for another try
        }
    }
}

async function main() {
    console.log(`Worker starting (mode=${config.mode}, extractor=${config.extractor})`);
    const receiver = serviceBus.createReceiver(config.serviceBus.queue);
    let processed = 0;

    while (true) {
        const messages = await receiver.receiveMessages(config.batchSize, { maxWaitTimeInMs: 5000 });
        if (messages.length === 0) {
            if (config.mode === "job") break; // queue drained: let the Job execution finish
            continue;
        }
        for (const msg of messages) {
            await handle(receiver, msg);
            processed++;
        }
    }

    console.log(`Queue drained, processed ${processed} message(s). Exiting.`);
    await receiver.close();
    await serviceBus.close();
}

main().catch(async (err) => {
    console.error(err);
    await serviceBus.close().catch(() => undefined);
    process.exit(1);
});
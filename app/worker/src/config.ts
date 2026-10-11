export const config = {
    // job  = drain the queue, then exit (how it runs as a Container Apps Job in Azure)
    // loop = keep polling forever (handy for local Docker Compose)
    mode: (process.env.WORKER_MODE ?? "job") as "job" | "loop",
    batchSize: Number(process.env.BATCH_SIZE ?? 5),
    // Keep in sync with the queue's MaxDeliveryCount.
    maxAttempts: Number(process.env.MAX_ATTEMPTS ?? 3),
    extractor: (process.env.EXTRACTOR ?? "mock") as "mock" | "azure",
    docIntel: {
        endpoint: process.env.DOCINTEL_ENDPOINT,
        key: process.env.DOCINTEL_KEY, // local only; Azure uses managed identity
    },
    storage: {
        connectionString: process.env.STORAGE_CONNECTION_STRING,
        accountUrl: process.env.STORAGE_ACCOUNT_URL,
        container: process.env.STORAGE_CONTAINER ?? "receipts",
    },
    serviceBus: {
        connectionString: process.env.SERVICEBUS_CONNECTION_STRING,
        namespace: process.env.SERVICEBUS_NAMESPACE,
        queue: process.env.SERVICEBUS_QUEUE ?? "receipts",
    },
    cosmos: {
        endpoint: process.env.COSMOS_ENDPOINT,
        key: process.env.COSMOS_KEY,
        emulator: process.env.COSMOS_EMULATOR === "true",
        database: process.env.COSMOS_DATABASE ?? "receiptsdb",
        container: process.env.COSMOS_CONTAINER ?? "receipts",
    },
};

export function must(value: string | undefined, name: string): string {
    if (!value) throw new Error(`Missing required env var ${name}`);
    return value;
}
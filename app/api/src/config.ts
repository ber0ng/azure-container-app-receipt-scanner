export const config = {
    port: Number(process.env.PORT ?? 3000),
    // locally api creates the blob container and cosmos db/container itself
    // in azure terraform owns those resources 
    localInit: process.env.LOCAL_INIT === "true",
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
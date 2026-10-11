import { DefaultAzureCredential, TokenCredential } from "@azure/identity";
import { BlobServiceClient } from "@azure/storage-blob";
import { ServiceBusClient } from "@azure/service-bus";
import { CosmosClient } from "@azure/cosmos";
import { config, must } from "./config";

let cred: TokenCredential | undefined;
export const credential = () => (cred ??= new DefaultAzureCredential());

const blobService = config.storage.connectionString
    ? BlobServiceClient.fromConnectionString(config.storage.connectionString)
    : new BlobServiceClient(must(config.storage.accountUrl, "STORAGE_ACCOUNT_URL"), credential());
export const blobContainer = blobService.getContainerClient(config.storage.container);

export const serviceBus = config.serviceBus.connectionString
    ? new ServiceBusClient(config.serviceBus.connectionString)
    : new ServiceBusClient(must(config.serviceBus.namespace, "SERVICEBUS_NAMESPACE"), credential());

const cosmos = new CosmosClient({
    endpoint: must(config.cosmos.endpoint, "COSMOS_ENDPOINT"),
    ...(config.cosmos.key ? { key: config.cosmos.key } : { aadCredentials: credential() }),
    connectionPolicy: config.cosmos.emulator ? { enableEndpointDiscovery: false } : undefined,
});
export const receipts = cosmos.database(config.cosmos.database).container(config.cosmos.container);
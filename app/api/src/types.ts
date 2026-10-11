export type ReceiptStatus = "pending" | "processing" | "completed" | "failed";

export interface ReceiptRecord {
    id: string;
    status: ReceiptStatus;
    blobName: string;
    contentType: string;
    originalName: string;
    createdAt: string;
    updatedAt: string;
    result?: unknown;
    error?: string;
}

export interface ReceiptMessage {
    receiptId: string;
    blobName: string;
}
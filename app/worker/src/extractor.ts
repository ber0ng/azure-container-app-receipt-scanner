import DocumentIntelligence, {
    AnalyzeOperationOutput,
    getLongRunningPoller,
    isUnexpected,
} from "@azure-rest/ai-document-intelligence";
import { AzureKeyCredential } from "@azure/core-auth";
import { config, must } from "./config";
import { credential } from "./clients";

// Retrying won't change the outcome, so the worker dead-letters these immediately.
export class PermanentError extends Error { }

export interface ReceiptResult {
    merchantName?: string;
    transactionDate?: string;
    total?: number;
    currency?: string;
    items: { description?: string; quantity?: number; totalPrice?: number }[];
    confidence?: number;
}

export interface Extractor {
    extract(document: Buffer): Promise<ReceiptResult>;
}

// Fake extraction so the whole pipeline runs locally with zero Azure dependencies.
class MockExtractor implements Extractor {
    async extract(_document: Buffer): Promise<ReceiptResult> {
        await new Promise((r) => setTimeout(r, 1500)); // pretend to think
        return {
            merchantName: "Mock Mart",
            transactionDate: new Date().toISOString().slice(0, 10),
            total: 349.75,
            currency: "PHP",
            items: [
                { description: "Iced coffee", quantity: 2, totalPrice: 240 },
                { description: "Ensaymada", quantity: 1, totalPrice: 109.75 },
            ],
            confidence: 0.99,
        };
    }
}

// Real extraction with the prebuilt receipt model.
class AzureExtractor implements Extractor {
    private client = DocumentIntelligence(
        must(config.docIntel.endpoint, "DOCINTEL_ENDPOINT"),
        config.docIntel.key ? new AzureKeyCredential(config.docIntel.key) : credential(),
    );

    async extract(document: Buffer): Promise<ReceiptResult> {
        const initial = await this.client
            .path("/documentModels/{modelId}:analyze", "prebuilt-receipt")
            .post({ contentType: "application/json", body: { base64Source: document.toString("base64") } });
        if (isUnexpected(initial)) throw new Error(`Analyze failed: ${initial.body.error.message}`);

        const done = await getLongRunningPoller(this.client, initial).pollUntilDone();
        const output = done.body as AnalyzeOperationOutput;
        const doc = output.analyzeResult?.documents?.[0];
        if (!doc) throw new PermanentError("No receipt detected in the document");

        const f = doc.fields ?? {};
        return {
            merchantName: f.MerchantName?.valueString,
            transactionDate: f.TransactionDate?.valueDate,
            total: f.Total?.valueCurrency?.amount,
            currency: f.Total?.valueCurrency?.currencyCode,
            items: (f.Items?.valueArray ?? []).map((item) => {
                const o = item.valueObject ?? {};
                return {
                    description: o.Description?.valueString,
                    quantity: o.Quantity?.valueNumber,
                    totalPrice: o.TotalPrice?.valueCurrency?.amount,
                };
            }),
            confidence: doc.confidence,
        };
    }
}

export const extractor: Extractor =
    config.extractor === "azure" ? new AzureExtractor() : new MockExtractor();
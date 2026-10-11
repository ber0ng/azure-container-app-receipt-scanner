import express, { NextFunction, Request, Response } from "express";
import multer from "multer";
import { randomUUID } from "node:crypto";
import { config } from "./config";
import { blobContainer, cosmos, receipts, serviceBus } from "./clients";
import { ReceiptMessage, ReceiptRecord } from "./types";

// formats doucment intelligence accepts
const ALLOWED_TYPES = new Set([
    "image/jpeg", "image/png", "image/bmp", "image/tiff", "image/heif", "application/pdf",
]);

const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 10 * 1024 * 1024 },
    fileFilter: (_req, file, cb) => cb(null, ALLOWED_TYPES.has(file.mimetype)),
});

const sender = serviceBus.createSender(config.serviceBus.queue);
const app = express();

app.get("/healthz", (_req, res) => {
    res.json({ status: "ok" });
});

app.post("/receipts", upload.single("file"), async (req, res) => {
    if (!req.file) {
        res.status(400).json({
            error: "Attach a receipt in the 'file' field (jpeg, png, bmp, tiff, heif or pdf, max 10 MB).",
        });
        return;
    }

    const id = randomUUID();
    const blobName = `uploads/${id}`;
    const now = new Date().toISOString();

    await blobContainer.getBlockBlobClient(blobName).uploadData(req.file.buffer, {
        blobHTTPHeaders: { blobContentType: req.file.mimetype },
    });

    const record: ReceiptRecord = {
        id,
        status: "pending",
        blobName,
        contentType: req.file.mimetype,
        originalName: req.file.originalname,
        createdAt: now,
        updatedAt: now,
    };
    await receipts.items.create(record);

    const message: ReceiptMessage = { receiptId: id, blobName };
    await sender.sendMessages({ body: message, messageId: id, contentType: "application/json" });

    res.status(202).location(`/receipts/${id}`).json(record);
});

app.get("/receipts/:id", async (req, res) => {
    const { resource } = await receipts.item(req.params.id, req.params.id).read<ReceiptRecord>();
    if (!resource) {
        res.status(404).json({ error: "Receipt not found" });
        return;
    }
    res.json(strip(resource));
});

app.get("/receipts", async (_req, res) => {
    const { resources } = await receipts.items
        .query<ReceiptRecord>("SELECT TOP 50 * FROM c ORDER BY c.createdAt DESC")
        .fetchAll();
    res.json(resources.map((r) => strip(r)));
});

// express 5 forwards rejected async handlers 
app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (err instanceof multer.MulterError && err.code === "LIMIT_FILE_SIZE") {
        res.status(413).json({ error: "File too large (max 10 MB)." });
        return;
    }
    console.error(err)
    res.status(500).json({ error: "Internal server error " });
});

// drop cosmos system properties from responses
function strip(r: ReceiptRecord): ReceiptRecord {
    return Object.fromEntries(Object.entries(r).filter(([k]) => !k.startsWith("_"))) as ReceiptRecord;
}

async function initLocal() {
    // emulators take a while to boot (cosmos especially) so need to retry
    for (let attempt = 1; ; attempt++) {
        try {
            await blobContainer.createIfNotExists();
            const { database } = await cosmos.databases.createIfNotExists({ id: config.cosmos.database });
            await database.containers.createIfNotExists({
                id: config.cosmos.container,
                partitionKey: { paths: ["/id"] },
            });
            console.log("Local init done (blob container + cosmos db/container)");
            return;
        } catch (err) {
            if (attempt >= 400) throw err;
            console.log(`Waiting for emulators (attempt ${attempt})...`);
            await new Promise((r) => setTimeout(r, 3000));
        }
    }
}

async function main() {
    if (config.localInit) await initLocal();
    const server = app.listen(config.port, () => console.log(`API listening on :${config.port}`));

    // container app sends sigterm on scale in / new revision
    process.on("SIGTERM", () => {
        server.close(async () => {
            await sender.close();
            await serviceBus.close();
            process.exit(0);
        });
    });
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
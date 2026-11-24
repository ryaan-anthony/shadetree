---
title: Import your clients from a spreadsheet
summary: Bring your client list over from a spreadsheet or another tool, check it before anything is added, and undo it if it's wrong.
category: clients-requests
topics: []
reviewed: 2026-11-24
screenshots:
  - name: import-clients
    path: /admin/clients/imports/new
---

Moving from a spreadsheet or another tool? Import your clients in one go. You see a preview
before anything is added, and you can undo the whole import afterwards.

![Import clients: choose your CSV file, then press Upload and preview](import-clients)

## Get your file ready

Export your clients as a CSV file from your spreadsheet or old tool. Or download **our
template** from the import page and fill it in. One client per row, with a row of column names
at the top.

## Import them

1. Open **Clients** and press **Import**.
2. Under **Upload a CSV file**, choose your file and press **Upload and preview**.
3. Under **Match your columns**, check where each of your columns **Goes to**. We guess from the
   column names; change any that are wrong, or choose **Don't import** to leave one out.
4. Press **Update preview** to see the first row as it'll be added.
5. Press **Import** (it says how many rows).

## Check what happened

When it's done, the import shows how many clients were **Added**, **Skipped** or
**Couldn't add**, and why:

- Rows with the same email or phone as a client you already have are listed under
  **Clients you already have**. Choose **Add them anyway** if they really are different people.
- **Download the report** lists every row that wasn't added, so you can fix them and import
  just those.

## Undo an import

Got the columns wrong? Within a week, press **Undo import**. It removes the clients this import
added that have no quotes, jobs or invoices yet, and leaves everyone else alone.

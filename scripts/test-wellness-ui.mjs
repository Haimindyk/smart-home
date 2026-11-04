// Actual components, synthetic owner data and a mocked AI boundary. No service calls.
import { build } from "esbuild";
import { chromium } from "@playwright/test";
import { createServer } from "node:http";
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";
import assert from "node:assert/strict";
const root = process.cwd(),
  temp = await mkdtemp(join(tmpdir(), "wellness-ui-"));
let browser, server;
try {
  await build({
    entryPoints: [resolve(root, "tests/wellness/browser/fixture.tsx")],
    outfile: join(temp, "fixture.js"),
    bundle: true,
    jsx: "automatic",
    define: { "process.env": "{}" },
    plugins: [
      {
        name: "synthetic-services",
        setup(b) {
          b.onResolve(
            {
              filter:
                /^(?:@\/lib\/(?:health\/(?:store|api|i18n)|supabase\/client)|\.\/(?:store|api))$/,
            },
            (args) => {
              if (
                args.path.startsWith(".") &&
                !args.importer.endsWith("/wellness-api.ts")
              )
                return;
              return {
                path: resolve(root, "tests/wellness/browser/services.ts"),
              };
            },
          );
        },
      },
    ],
  });
  const cssFiles = await readdir(join(root, ".next/static/chunks"));
  const css = (
    await Promise.all(
      cssFiles
        .filter((f) => f.endsWith(".css"))
        .map((f) => readFile(join(root, ".next/static/chunks", f), "utf8")),
    )
  ).join("\n");
  const js = await readFile(join(temp, "fixture.js"));
  server = createServer((req, res) => {
    if (req.url === "/fixture.js") {
      res.setHeader("Content-Type", "text/javascript");
      res.end(js);
    } else if (req.url === "/styles.css") {
      res.setHeader("Content-Type", "text/css");
      res.end(css);
    } else {
      const he = req.url.includes("he");
      res.end(
        `<html dir="${he ? "rtl" : "ltr"}" lang="${he ? "he" : "en"}"><head><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/styles.css"></head><body><div id="root"></div><script src="/fixture.js"></script></body></html>`,
      );
    }
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const base = `http://127.0.0.1:${server.address().port}`;
  browser = await chromium.launch({
    headless: true,
    ...(process.env.CHROMIUM_PATH
      ? { executablePath: process.env.CHROMIUM_PATH }
      : {}),
    args: ["--no-sandbox"],
  });
  const actions = (page) => page.evaluate(() => window.wellnessFixture.calls);
  for (const language of ["he", "en"]) {
    const he = language === "he",
      page = await browser.newPage({ viewport: { width: 390, height: 844 } }),
      errors = [];
    page.on("pageerror", (e) => {
      errors.push(e.message);
      process.stderr.write("Browser error: " + e.message + "\n");
    });
    await page.goto(base + "/?lang=" + language);
    await page
      .getByRole("button", {
        name: he ? "בנייה ושיפור תוכנית" : "Build or improve a plan",
      })
      .click();
    const generate = page.getByRole("button", {
      name: he ? "הכנת הצעה לבדיקה" : "Prepare a proposal to review",
    });
    await generate.waitFor();
    await generate.click();
    const approve = page.getByRole("button", {
      name: he ? "אישור ושמירת השינוי" : "Approve and save changes",
    });
    await approve.waitFor();
    assert(
      !(await actions(page)).some(
        (c) => c.action === "apply" || c.table === "workout_plans",
      ),
      "generation never auto-applies",
    );
    await approve.click();
    await page
      .getByRole("status")
      .filter({
        hasText: he ? "השינוי שאישרת נשמר" : "Your approved change was saved",
      })
      .waitFor();
    assert.equal(
      (await actions(page)).filter((c) => c.action === "apply").length,
      1,
    );
    assert(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth + 1,
      ),
      "mobile page should not overflow",
    );
    await page
      .getByRole("button", {
        name: he ? "הוספת ארוחה" : "Add meal",
        exact: true,
      })
      .click();
    await page
      .getByRole("button", {
        name: he ? "כתבו מה אכלתם" : "Describe your meal",
      })
      .click();
    await page
      .getByLabel(he ? "מה אכלתם וכמה?" : "What did you eat, and how much?")
      .fill(he ? "אכלתי כוס אורז מבושל" : "I ate a cup of cooked rice");
    await page
      .getByRole("button", {
        name: he ? "הערכת הארוחה לבדיקה" : "Estimate meal for review",
      })
      .click();
    await page.getByText("אורז לבן מבושל", { exact: true }).waitFor();
    assert(
      !(await actions(page)).some((c) => c.table === "meals"),
      "food estimate never auto-saves",
    );
    await page
      .getByRole("button", {
        name: he ? "אישור והוספה ליומן" : "Confirm & save to diary",
      })
      .click();
    assert.equal(
      (await actions(page)).filter((c) => c.table === "meals").length,
      1,
    );
    const optin = page.getByRole("button", {
      name: he
        ? "מאשר/ת השתתפות באימון המודלים שלנו"
        : "Opt in to training our models",
    });
    await optin.click();
    await page
      .getByLabel(he ? "בחירת רשומה מהיומן שלי" : "Choose a saved record")
      .selectOption("00000000-0000-4000-8000-000000000001");
    await page
      .getByLabel(
        he
          ? "תיאור הבקשה המקורי, בלי מידע מזהה"
          : "Original request without identifying information",
      )
      .fill("I ate an apple");
    const contribute = page.getByRole("button", {
      name: he ? "שיתוף הדוגמה שבחרתי" : "Contribute this example",
    });
    assert(
      await contribute.isDisabled(),
      "consent alone must not share a diary entry",
    );
    await page
      .getByLabel(
        he
          ? "בדקתי את הרשומה ואני מאשר/ת לשתף את הדוגמה הזו לצורך אימון."
          : "I reviewed this record and approve sharing this specific example for training.",
      )
      .check();
    await contribute.click();
    await page
      .getByText(
        he
          ? "הדוגמה נשמרה לבדיקה. היא עדיין אינה נתון אימון מאומת."
          : "Saved for review. This is not yet a verified training label.",
      )
      .waitFor();
    await page
      .getByRole("button", {
        name: he
          ? "ביטול הסכמה ומחיקת הדוגמאות"
          : "Revoke consent and delete examples",
      })
      .click();
    await optin.waitFor();
    const composer = page.getByLabel(
      he ? "מה תרצו לשאול?" : "What would you like to ask?",
    );
    await composer.fill(
      he
        ? "איך לחלק חלבון במשך היום?"
        : "How should I spread protein through the day?",
    );
    await page
      .getByRole("button", { name: he ? "שליחה למאמן" : "Send to coach" })
      .click();
    const conversation = page.getByRole("log", {
      name: he ? "השיחה עם המאמן" : "Conversation with your coach",
    });
    await conversation.getByText(/בדקו את הכמויות הרשומות/).waitFor();
    assert.equal(
      (await actions(page)).filter((c) => c.action === "send").length,
      1,
    );
    assert.equal(
      (await actions(page)).find((c) => c.action === "send").diary,
      false,
      "diary is opt-in",
    );
    assert.equal(
      (await actions(page)).filter((c) => c.action === "illustration").length,
      0,
      "closed references never start illustration generation",
    );
    assert.equal(
      await page.evaluate(() => window.chatInjected),
      undefined,
      "model text cannot execute HTML",
    );
    await conversation.getByRole("button", { name: "איך לחלק חלבון?" }).click();
    assert.equal(
      (await actions(page)).filter((c) => c.action === "send").length,
      1,
      "follow-up inserts a draft without sending",
    );
    await page
      .getByLabel(
        he
          ? "לצרף סיכום מהיומן שלי: ערכים שנרשמו היום, היעד השמור ואימונים אחרונים. בלי תמונות, שם או הערות אישיות."
          : "Include a diary summary: today’s logged nutrients, saved target and recent workouts. No photos, name or personal notes.",
      )
      .check();
    await page
      .getByRole("button", { name: he ? "שליחה למאמן" : "Send to coach" })
      .click();
    assert.equal(
      (await actions(page)).filter((c) => c.action === "send").at(-1).diary,
      true,
    );
    await conversation.locator("section").nth(1).waitFor();
    await page.reload();
    await page.getByRole("log").locator("section").nth(1).waitFor();
    assert(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth + 1,
      ),
      "chat fits mobile width",
    );
    page.once("dialog", (dialog) => dialog.accept());
    await page
      .getByRole("button", { name: he ? "מחיקת שיחה" : "Clear chat" })
      .click();
    await page
      .getByText(
        he
          ? "אפשר להתחיל משאלה: איך לחלק חלבון לאורך היום, או מה ההבדל בין Full Body ל־AB?"
          : "Start with a question: how should I spread protein through the day, or how does Full Body compare with AB?",
      )
      .waitFor();
    assert.deepEqual(errors, []);
    await page.close();
  }
  const minor = await browser.newPage();
  await minor.goto(base + "/?minor=1");
  await minor.getByRole("button", { name: "Build or improve a plan" }).click();
  assert(
    await minor
      .getByRole("button", { name: "Prepare a proposal to review" })
      .isDisabled(),
    "minor cannot request AI",
  );
  await minor.close();
  console.log(
    "PASS: Hebrew/English mobile proposal approval, food estimate confirmation, separate training consent, per-example approval/revocation, no automatic writes, adult gate, chat follow-ups/history/deletion, opt-in context and escaped model text. Synthetic services; live model not tested.",
  );
} finally {
  await browser?.close();
  await new Promise((r) => (server ? server.close(r) : r()));
  await rm(temp, { recursive: true, force: true });
}

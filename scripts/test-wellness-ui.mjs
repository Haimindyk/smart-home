// Actual components, synthetic owner data and a mocked AI boundary. No service calls.
import { build } from "esbuild";
import { chromium } from "@playwright/test";
import { createServer } from "node:http";
import { mkdtemp, mkdir, readFile, readdir, rm } from "node:fs/promises";
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
                /^(?:@\/lib\/(?:health\/(?:store|api|i18n)|supabase\/client|store\/app-store|identity)|\.\/(?:store|api))$/,
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
  server = createServer(async (req, res) => {
    const path = new URL(req.url, "http://localhost").pathname;
    if (
      path.startsWith("/_next/static/media/") &&
      /^[a-zA-Z0-9_.-]+\.woff2?$/.test(path.split("/").at(-1))
    ) {
      try {
        res.setHeader("Content-Type", "font/woff2");
        res.end(
          await readFile(
            join(root, ".next/static/media", path.split("/").at(-1)),
          ),
        );
      } catch {
        res.statusCode = 404;
        res.end();
      }
      return;
    }

    if (req.url === "/fixture.js") {
      res.setHeader("Content-Type", "text/javascript");
      res.end(js);
    } else if (req.url === "/styles.css") {
      res.setHeader("Content-Type", "text/css");
      res.end(css);
    } else {
      const he = req.url.includes("he");
      res.end(
        `<html dir="${he ? "rtl" : "ltr"}" lang="${he ? "he" : "en"}"><head><style>:root{--font-heebo:${css.match(/--font-heebo:([^;}]+)/)?.[1] ?? "Arial,sans-serif"};font-family:var(--font-heebo),Arial,sans-serif}</style><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/styles.css"></head><body><div id="root"></div><script src="/fixture.js"></script></body></html>`,
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
    args: [
      "--no-sandbox",
      "--use-fake-device-for-media-stream",
      "--use-fake-ui-for-media-stream",
    ],
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
        name: he ? "תוכנית עם AI" : "Plan with AI",
      })
      .click();
    const generate = page.getByRole("button", {
      name: he ? "יצירת תוכנית" : "Create program",
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
      .getByRole("button", { name: he ? "סגירה" : "Close", exact: true })
      .click();
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
        name: he ? "הצגת הערכה" : "Show estimate",
      })
      .click();
    await page.getByText("אורז לבן מבושל", { exact: true }).waitFor();
    assert(
      !(await actions(page)).some((c) => c.table === "meals"),
      "food estimate never auto-saves",
    );
    const nutritionCalls = (await actions(page)).filter(
      (c) => c.action === "nutrition",
    ).length;
    await page
      .getByRole("button", { name: he ? "מוצר" : "Product", exact: true })
      .click();
    const labelSection = page.getByRole("region", {
      name: he ? "ערכי מוצר מהאריזה" : "Product label values",
    });
    await labelSection
      .getByLabel(he ? "ברקוד המוצר" : "Product barcode", { exact: true })
      .fill("12345678");
    await labelSection
      .getByRole("button", {
        name: he ? "איתור מוצר" : "Find product",
        exact: true,
      })
      .click();
    await labelSection
      .getByText("Synthetic packaged food", { exact: true })
      .waitFor();
    const addProduct = labelSection.getByRole("button", {
      name: he ? "הוספה לארוחה" : "Add to meal",
    });
    assert(
      await addProduct.isDisabled(),
      "database values require package confirmation",
    );
    const labelConfirm = labelSection.getByLabel(
      he
        ? "בדקתי שהמוצר, היחידה והערכים תואמים לאריזה"
        : "I checked that the product, unit and values match the package",
    );
    await labelConfirm.check();
    await addProduct.click();
    await labelSection
      .getByLabel(he ? "ברקוד המוצר" : "Product barcode", { exact: true })
      .fill("87654321");
    await labelSection
      .getByRole("button", {
        name: he ? "איתור מוצר" : "Find product",
        exact: true,
      })
      .click();
    const printedCalories = labelSection.getByLabel(
      he ? "קלוריות (קק״ל)" : "Calories (kcal)",
      { exact: true },
    );
    await printedCalories.waitFor();
    assert.equal(
      await printedCalories.inputValue(),
      "",
      "missing calories must not become zero",
    );
    await labelSection
      .getByLabel(he ? "שם המוצר שעל האריזה" : "Product name on package")
      .fill("Printed package test");
    await labelSection
      .getByLabel(
        he ? "הערכים המודפסים הם לכמות" : "Printed values are per amount",
      )
      .fill("40");
    await printedCalories.fill("100");
    await labelSection
      .getByLabel(he ? "חלבון (גרם)" : "Protein (g)", { exact: true })
      .fill("4");
    await labelSection
      .getByLabel(he ? "פחמימות (גרם)" : "Carbohydrate (g)", { exact: true })
      .fill("12");
    await labelSection
      .getByLabel(he ? "שומן (גרם)" : "Fat (g)", { exact: true })
      .fill("4");
    await labelConfirm.check();
    await addProduct.click();
    assert.equal(
      (await actions(page)).filter((c) => c.action === "nutrition").length,
      nutritionCalls,
      "label flow never calls nutrition AI",
    );
    assert(
      !(await actions(page)).some((c) => c.table === "meals"),
      "label selection only edits the draft",
    );
    assert(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth + 1,
      ),
      "product label fits mobile width",
    );
    await page
      .getByRole("button", {
        name: he ? "שמירה ביומן" : "Save to diary",
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
          ? "לצרף סיכום יומן: ערכי היום, היעד ואימונים אחרונים"
          : "Include diary summary: today’s nutrients, target and recent workouts",
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
      .getByText(he ? "על מה נדבר?" : "What’s on your mind?", { exact: true })
      .waitFor();
    assert.deepEqual(errors, []);
    await page.close();
  }
  if (process.env.WELLNESS_SCREENSHOTS_DIR) {
    await mkdir(process.env.WELLNESS_SCREENSHOTS_DIR, { recursive: true });
    for (const lang of ["he", "en"]) {
      const preview = await browser.newPage({
        viewport: { width: 390, height: 844 },
      });
      preview.on("pageerror", (e) =>
        process.stderr.write("Preview error: " + e.message + "\n"),
      );
      await preview.goto(base + "/?preview=1&lang=" + lang);
      for (const [screen, he, en] of [
        ["nutrition", "היום", "Today"],
        ["workouts", "אימונים", "Workouts"],
        ["coach", "צ׳אט AI", "AI chat"],
        ["settings", "הגדרות", "Settings"],
        ["progress", "התקדמות", "Progress"],
      ]) {
        if (screen === "settings")
          await preview.locator("#health-settings-button").click();
        else
          await preview
            .getByRole("tab", { name: lang === "he" ? he : en, exact: true })
            .click();
        await preview
          .getByRole("tabpanel")
          .locator("section")
          .first()
          .waitFor();
        await preview.evaluate(async () => {
          await document.fonts.ready;
          window.scrollTo(0, 0);
        });
        await preview.screenshot({
          path: join(
            process.env.WELLNESS_SCREENSHOTS_DIR,
            `${lang}-${screen}.png`,
          ),
          animations: "disabled",
        });
      }
      await preview.close();
    }
  }
  const minor = await browser.newPage();
  await minor.goto(base + "/?minor=1");
  await minor.getByRole("button", { name: "Plan with AI" }).click();
  assert(
    await minor.getByRole("button", { name: "Create program" }).isDisabled(),
    "minor cannot request AI",
  );
  await minor.close();
  const photo = await browser.newPage({
    viewport: { width: 390, height: 844 },
  });
  await photo.goto(base + "/?photo-test=1");
  await photo.getByRole("button", { name: "Add meal", exact: true }).click();
  await photo
    .getByRole("button", { name: "Photograph a meal", exact: true })
    .click();
  await photo.waitForFunction(
    () => document.querySelector("video")?.videoWidth > 0,
  );
  await photo.evaluate(() => {
    document.querySelector("[role=dialog]").scrollTop = 0;
  });
  const cameraBounds = await photo.getByRole("dialog").boundingBox();
  assert(
    cameraBounds &&
      Math.abs(cameraBounds.x) < 1 &&
      Math.abs(cameraBounds.y) < 1 &&
      cameraBounds.width >= 389 &&
      cameraBounds.height >= 843,
    "camera fills the viewport without popup translation: " +
      JSON.stringify({
        cameraBounds,
        styles: await photo.getByRole("dialog").evaluate((el) => ({
          translate: getComputedStyle(el).translate,
          transform: getComputedStyle(el).transform,
          inset: getComputedStyle(el).inset,
          margin: getComputedStyle(el).margin,
        })),
      }),
  );
  if (process.env.WELLNESS_SCREENSHOTS_DIR)
    await photo.screenshot({
      path: join(
        process.env.WELLNESS_SCREENSHOTS_DIR,
        "meal-camera-verified.png",
      ),
      animations: "disabled",
    });
  await photo
    .getByRole("button", { name: "Take photo", exact: true })
    .dblclick();
  await photo.getByRole("dialog").waitFor({ state: "hidden" });
  assert.equal(
    (await actions(photo)).filter((c) => c.table === "meals").length,
    1,
    "photo saves automatically once",
  );
  const savedMealId = await photo.evaluate(
    () => window.wellnessFixture.meals().at(-1).id,
  );
  await photo.getByRole("button", { name: "Photo meal", exact: true }).click();
  await photo.getByLabel("What should change?").fill("זה דג ולא חזה עוף");
  await photo.getByRole("button", { name: "Update meal", exact: true }).click();
  await photo.getByText("Meal updated", { exact: true }).waitFor();
  assert.equal(
    (await actions(photo)).filter((c) => c.table === "meals").length,
    2,
    "correction updates the existing meal",
  );
  assert.equal(
    await photo.evaluate(
      () =>
        window.wellnessFixture
          .meals()
          .filter((m) => m.data.name === "Photo meal").length,
    ),
    1,
    "correction does not insert another meal",
  );
  assert.equal(
    await photo.evaluate(() => window.wellnessFixture.meals().at(-1).id),
    savedMealId,
    "correction preserves meal identity",
  );
  await photo.close();
  for (const scenario of ["photo-empty", "photo-retry"]) {
    const p = await browser.newPage({ viewport: { width: 390, height: 844 } });
    await p.goto(base + "/?" + scenario + "=1");
    await p.getByRole("button", { name: "Add meal", exact: true }).click();
    await p
      .getByRole("button", { name: "Photograph a meal", exact: true })
      .click();
    await p.waitForFunction(
      () => document.querySelector("video")?.videoWidth > 0,
    );
    await p.getByRole("button", { name: "Take photo", exact: true }).click();
    await p.getByRole("alert").waitFor();
    assert.equal(
      (await actions(p)).filter((c) => c.table === "meals").length,
      0,
      "failed or empty analysis creates no meal",
    );
    if (scenario === "photo-empty") {
      await p
        .getByText("No food identified. Try a clearer, closer photo.", {
          exact: true,
        })
        .waitFor();
      assert.equal(
        await p.getByRole("button", { name: "Retry", exact: true }).count(),
        0,
        "no repeat quota spend on the same empty result",
      );
    } else {
      await p.getByRole("button", { name: "Retry", exact: true }).click();
      await p.getByRole("dialog").waitFor({ state: "hidden" });
      assert.equal(
        (await actions(p)).filter((c) => c.table === "meals").length,
        1,
        "retry saves exactly one meal",
      );
    }
    await p.close();
  }
  const noAI = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await noAI.goto(base + "/?ai-off=1");
  await noAI.getByRole("button", { name: "Add meal", exact: true }).click();
  await noAI
    .getByRole("button", { name: "Packaged product", exact: true })
    .click();
  await noAI.getByLabel("Product barcode", { exact: true }).fill("12345678");
  const lookup = noAI.getByRole("button", {
    name: "Find product",
    exact: true,
  });
  assert(await lookup.isEnabled(), "barcode lookup works with AI disabled");
  await lookup.click();
  await noAI.getByText("Synthetic packaged food", { exact: true }).waitFor();
  assert(
    !(await actions(noAI)).some((c) => c.action === "nutrition"),
    "disabled AI is never used for labels",
  );
  await noAI.close();

  console.log(
    "PASS: Hebrew/English mobile proposal approval, food estimate confirmation, non-AI barcode/printed-label flow with AI disabled, separate training consent, per-example approval/revocation, automatic photo save and saved-meal correction, adult gate, chat follow-ups/history/deletion, opt-in context and escaped model text. Synthetic services; live model not tested.",
  );
} finally {
  await browser?.close();
  await new Promise((r) => (server ? server.close(r) : r()));
  await rm(temp, { recursive: true, force: true });
}

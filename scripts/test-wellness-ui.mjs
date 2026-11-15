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
                !/\/(?:wellness-api|meal-editing)\.ts$/.test(args.importer)
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
      res.setHeader("Content-Type", "text/javascript; charset=utf-8");
      res.end(js);
    } else if (req.url === "/styles.css") {
      res.setHeader("Content-Type", "text/css; charset=utf-8");
      res.end(css);
    } else {
      const he = req.url.includes("he");
      res.end(
        `<html dir="${he ? "rtl" : "ltr"}" lang="${he ? "he" : "en"}"><head><meta charset="utf-8"><style>:root{--font-heebo:${css.match(/--font-heebo:([^;}]+)/)?.[1] ?? "Arial,sans-serif"};font-family:var(--font-heebo),Arial,sans-serif}</style><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/styles.css"></head><body><div id="root"></div><script src="/fixture.js"></script></body></html>`,
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
    const writesBeforeFavorites = (await actions(page)).filter(c=>c.table === "meals").length;
    await page.getByRole("button", { name:he ? "ארוחות מועדפות" : "Favorite meals", exact:true }).click();
    await page.getByRole("heading", { name:he ? "ארוחות מועדפות" : "Favorite meals", exact:true }).waitFor();
    assert.equal(await page.getByRole("button", { name:he ? "מועדפות" : "Favorites",exact:true }).getAttribute("aria-pressed"), "true", "favorite meals opens the correct list directly");
    await page.getByRole("heading", { name:he ? "עוד אין ארוחות מועדפות" : "No favorite meals yet", exact:true }).waitFor();
    if (process.env.WELLNESS_SCREENSHOTS_DIR) await page.screenshot({ path:join(process.env.WELLNESS_SCREENSHOTS_DIR,language+"-empty-favorites.png"),animations:"disabled" });
    await page.getByRole("button", { name:he ? "לארוחות האחרונות" : "Browse recent meals",exact:true }).click();
    await page.getByRole("heading", { name:he ? "ארוחות קודמות" : "Previous meals",exact:true }).waitFor();
    await page.getByLabel(he ? "חיפוש ארוחה" : "Search meals",{exact:true}).waitFor();
    assert.equal((await actions(page)).filter(c=>c.table === "meals").length,writesBeforeFavorites,"browsing favorites and recent meals does not change the diary");
    await page.getByRole("button", { name:he ? "סגירה" : "Close",exact:true }).click();
    await page.getByRole("button", { name:he ? "הוספת ארוחה" : "Add meal",exact:true }).click();
    await page
      .getByRole("button", {
        name: he ? "כתבו מה אכלתם" : "Describe your meal",
      })
      .click();
    const descriptionSheet = page.getByRole("dialog", { name:he ? "תיאור ארוחה" : "Describe your meal", exact:true });
    await descriptionSheet.getByRole("heading", { name:he ? "תיאור ארוחה" : "Describe your meal", exact:true }).waitFor();
    assert.equal(await descriptionSheet.getByRole("button", { name:he ? "סגירה" : "Close", exact:true }).count(), 1, "meal entry has one shared close action");
    const descriptionBox = await descriptionSheet.getByRole("textbox").boundingBox();
    assert(descriptionBox && descriptionBox.height>=170, "meal description has a spacious text field");
    assert.equal(
      await page
        .getByRole("group", {
          name: he ? "דרך הוספה" : "Entry method",
          exact: true,
        })
        .count(),
      0,
      "description skips method chooser",
    );
    assert.equal(
      await page
        .getByRole("button", {
          name: he ? "שמירה ביומן" : "Save to diary",
          exact: true,
        })
        .count(),
      0,
      "description hides empty save",
    );
    assert.equal(
      await page
        .getByText(he ? "חיפוש מזון או מוצר" : "Find a food or product", {
          exact: true,
        })
        .count(),
      0,
      "description skips duplicate food search",
    );
    if (process.env.WELLNESS_SCREENSHOTS_DIR)
      await page.screenshot({
        path: join(
          process.env.WELLNESS_SCREENSHOTS_DIR,
          language + "-direct-description.png",
        ),
        animations: "disabled",
      });
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
        name: he ? "מוצר ארוז" : "Packaged product",
        exact: true,
      })
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
    const productAmount = labelSection.getByRole("region", { name: he ? "כמות המוצר" : "Product amount", exact: true });
    await productAmount.getByLabel(he ? "כמות שאכלת (g)" : "Amount eaten (g)", { exact: true }).fill("65");
    assert(await productAmount.isVisible(), "gram selection is directly visible after barcode lookup");
    await productAmount.getByRole("button", { name: he ? "יחידות" : "Units", exact: true }).click();
    await productAmount.getByLabel(he ? "מספר יחידות" : "Number of units", { exact: true }).fill("2");
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
    assert(await addProduct.isDisabled(), "unknown unit size cannot silently become 100 g");
    await productAmount.getByLabel(he ? "גרם ליחידה" : "g per unit", { exact: true }).fill("30");
    assert(await addProduct.isEnabled(), "explicit 30 g units allow adding the product");
    if (process.env.WELLNESS_SCREENSHOTS_DIR) await page.screenshot({ path: join(process.env.WELLNESS_SCREENSHOTS_DIR, language + "-product-units.png"), animations: "disabled" });
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
    await labelSection.getByLabel(he ? "כמות שאכלת (g)" : "Amount eaten (g)", { exact: true }).fill("40");
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
    const productMeal = await page.evaluate(() => window.wellnessFixture.meals().at(-1).data);
    assert.equal(productMeal.items[0].quantity, 60, "two scanned 30 g units persist as 60 g");
    assert.equal(productMeal.items[1].quantity, 40, "printed-label grams persist exactly");
    assert.equal(productMeal.items[0].food.per100.kcal, 250, "quantity edits do not rewrite source per100");
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
    const weighed = page.getByLabel(he ? "כל כמויות המרכיבים נמדדו במשקל, ולא הוערכו" : "All ingredient amounts were weighed, not estimated", { exact: true });
    await weighed.check();
    const measuredLabel = he ? "Synthetic apple (גרם שנמדד)" : "Synthetic apple (measured g)";
    assert.equal(await page.getByLabel(measuredLabel, { exact: true }).inputValue(), "", "AI quantities are never prefilled as measured weights");
    await page.getByLabel(measuredLabel, { exact: true }).fill("80");
    const sourcePicker = page.getByLabel(he ? "בחירת רשומה מהיומן שלי" : "Choose a saved record");
    await sourcePicker.selectOption(await page.evaluate(() => window.wellnessFixture.meals().at(-1).id));
    assert(!(await weighed.isChecked()), "measurement claims reset when the selected meal changes");
    await sourcePicker.selectOption("00000000-0000-4000-8000-000000000001");
    await page.getByLabel(he ? "תיאור הבקשה המקורי, בלי מידע מזהה" : "Original request without identifying information").fill("I ate an apple");
    await weighed.check();
    assert.equal(await page.getByLabel(measuredLabel, { exact: true }).inputValue(), "");
    const approveExample = page.getByLabel(he ? "בדקתי את הרשומה ואני מאשר/ת לשתף את הדוגמה הזו לצורך אימון." : "I reviewed this record and approve sharing this specific example for training.");
    await approveExample.check();
    assert(await contribute.isDisabled(), "approval without every measured weight cannot submit a weighed example");
    await page.getByLabel(measuredLabel, { exact: true }).fill("80");
    assert(!(await approveExample.isChecked()), "changing a measurement requires approval of the changed example");
    await approveExample.check();
    await contribute.click();
    await page.waitForFunction(() => window.wellnessFixture.trainingExamples().length === 2);
    const measuredExample = await page.evaluate(() => window.wellnessFixture.trainingExamples().at(-1));
    assert.equal(measuredExample.label_quality, "weighed");
    assert.deepEqual(measuredExample.measurement_provenance, { version: 1, method: "user_reported_grams", source_version: 1 });
    assert.equal(measuredExample.items[0].quantity, 80);
    assert.equal(await page.evaluate(() => window.wellnessFixture.meals()[0].data.items[0].quantity), 100, "training measurements do not rewrite the diary");
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
    await page.locator(".health-chat-options > summary").click();
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
  for (const lang of ["he", "en"]) {
    const he=lang === "he", food=await browser.newPage({viewport:{width:390,height:844}});
    await food.goto(base+"/?ai-disabled=1&lang="+lang);
    const before=await food.evaluate(()=>window.wellnessFixture.meals().length);
    await food.getByRole("button",{name:he?"הוספת ארוחה":"Add meal",exact:true}).click();
    await food.getByRole("button",{name:he?"מאגר מזון":"Food database",exact:true}).click();
    await food.getByRole("heading",{name:he?"חיפוש מזון":"Search foods",exact:true}).waitFor();
    assert.equal(await food.getByRole("button",{name:he?"שמירה ביומן":"Save to diary",exact:true}).count(),0,"empty search does not offer an unusable diary save");
    await food.getByRole("button",{name:he?"ברקוד":"Barcode",exact:true}).waitFor();
    const searchField=food.getByLabel(he?"שם מזון או מוצר":"Food or product name",{exact:true});
    await searchField.fill("טחינה");
    assert.equal(await food.getByText(he?"לא נמצאו מזונות. אפשר להוסיף ידנית.":"No foods found. You can add one manually.",{exact:true}).count(),0,"typing is not incorrectly reported as a failed search");
    await food.getByRole("button",{name:he?"חיפוש במאגר המזון":"Search food database",exact:true}).click();
    await food.getByRole("button",{name:/טחינה גולמית/}).waitFor();
    if(process.env.WELLNESS_SCREENSHOTS_DIR) await food.screenshot({path:join(process.env.WELLNESS_SCREENSHOTS_DIR,lang+"-tahini-search.png"),animations:"disabled"});
    await searchField.fill("");
    if(process.env.WELLNESS_SCREENSHOTS_DIR) await food.screenshot({path:join(process.env.WELLNESS_SCREENSHOTS_DIR,lang+"-food-search.png"),animations:"disabled"});
    await food.getByRole("button",{name:he?"שמורים":"Saved",exact:true}).click();
    await food.getByLabel(he?"שם מזון או מוצר":"Food or product name",{exact:true}).fill("missing saved food");
    assert.equal((await actions(food)).filter(c=>c.action==="food-lookup").length,1,"typing in saved foods does not make network requests");
    await food.getByRole("button",{name:he?"חיפוש":"Search",exact:true}).click();
    assert.equal((await actions(food)).filter(c=>c.action==="food-lookup").length,2,"explicit search works even when Saved was selected");
    await food.getByRole("button",{name:he?"מזון חדש / הזנה ידנית":"New food / manual entry",exact:true}).click();
    assert(!(await food.getByLabel(he?"סיבים (ג׳)":"Fiber (g)",{exact:true}).isVisible()),"optional manual nutrients start collapsed");
    await food.getByLabel(he?"שם מזון":"Food name",{exact:true}).fill("Manual fixture");
    for(const [label,value] of [[he?"קלוריות":"Calories","165"],[he?"חלבון (ג׳)":"Protein (g)","31"],[he?"פחמימות (ג׳)":"Carbs (g)","0"],[he?"שומן (ג׳)":"Fat (g)","3.6"],[he?"כמות שנאכלה":"Amount eaten","50"]]) await food.getByLabel(label,{exact:true}).fill(value);
    await food.locator(".food-picker details").filter({has:food.getByText(he?"ערכים נוספים":"More nutrients",{exact:true})}).locator("summary").click();
    await food.getByLabel(he?"סיבים (ג׳)":"Fiber (g)",{exact:true}).fill("2.5");
    if(process.env.WELLNESS_SCREENSHOTS_DIR) await food.screenshot({path:join(process.env.WELLNESS_SCREENSHOTS_DIR,lang+"-manual-food.png"),animations:"disabled"});
    await food.getByRole("button",{name:he?"הוספת מזון":"Add food",exact:true}).click();
    await food.locator(".meal-review-item h3").filter({hasText:"Manual fixture"}).waitFor();
    assert.equal(await food.evaluate(()=>window.wellnessFixture.meals().length),before,"adding manual food only changes the draft");
    await food.getByRole("button",{name:he?"שמירה ביומן":"Save to diary",exact:true}).click();
    const saved=await food.evaluate(()=>window.wellnessFixture.meals().at(-1));
    assert.equal(saved.data.items[0].quantity,50);assert.equal(saved.data.items[0].food.per100.fiber,2.5);
    assert(!(await actions(food)).some(c=>c.action==="nutrition"),"manual nutrition never needs AI");
    await food.close();
  }
  for (const lang of ["he", "en"]) {
    const mobile = await browser.newPage({ viewport: { width:390, height:844 } });
    await mobile.goto(base + "/?preview=1&daily-populated=1&lang=" + lang);
    await mobile.getByRole("tab", { name:lang === "he" ? "צ׳אט AI" : "AI chat", exact:true }).click();
    const starter = mobile.getByRole("button", { name:lang === "he" ? "איך לחלק חלבון ביום?" : "How can I spread protein through the day?", exact:true });
    await starter.click();
    assert.equal(await mobile.getByLabel(lang === "he" ? "מה תרצו לשאול?" : "What would you like to ask?").inputValue(), await starter.textContent(), "conversation starters insert an editable draft");
    assert.equal((await actions(mobile)).filter(c=>c.action === "send").length, 0, "choosing a starter never sends a message");
    assert(!(await mobile.locator(".health-chat-options").evaluate(e=>e.open)), "secondary chat controls start collapsed");
    for (const width of [390,320]) {
      await mobile.setViewportSize({ width, height:844 });
      await mobile.evaluate(async()=>{ await document.fonts.ready; window.scrollTo(0,0); });
      const send = await mobile.locator(".health-chat-send").boundingBox();
      const nav = await mobile.locator(".health-bottom-nav").boundingBox();
      assert(send && nav && send.y+send.height < nav.y, "chat send action is visible above mobile navigation");
      assert(await mobile.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1), "chat has no horizontal page overflow");
    }
    await mobile.getByRole("tab", { name:lang === "he" ? "אימונים" : "Workouts", exact:true }).click();
    const plan = await mobile.locator(".workout-plan-tile").first().boundingBox();
    const planGrid = await mobile.locator(".workout-plan-grid").boundingBox();
    assert(plan && planGrid && Math.abs(plan.width-planGrid.width)<2, "mobile workout plan fills its available row");
    await mobile.getByRole("tab",{name:lang === "he" ? "התקדמות" : "Progress",exact:true}).click();
    assert.equal(await mobile.locator(".health-progress-single").count(),1,"a single logged day shows its value instead of a misleading graph");
    assert.equal(await mobile.locator(".health-progress-chart svg").count(),0,"one point never renders an empty trend chart");
    const intake = mobile.locator(".health-progress > details").filter({has:mobile.getByText(lang === "he" ? "צריכה מול יעד יומי" : "Intake vs daily goal",{exact:true})});
    assert(!(await intake.evaluate(e=>e.open)),"detailed intake tables start collapsed");
    await intake.locator("summary").click();
    assert(await intake.getByRole("table").isVisible(),"the complete intake history stays available");
    await mobile.getByRole("button",{name:lang === "he" ? "שבוע" : "Week",exact:true}).click();
    assert.equal(await mobile.getByRole("button",{name:lang === "he" ? "שבוע" : "Week",exact:true}).getAttribute("aria-pressed"),"true");
    assert(await mobile.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),"progress fits a 320px phone");
    await mobile.goto(base+"/?preview=1&daily-populated=1&progress-series=1&nutrition-only=1&lang="+lang);
    await mobile.getByRole("tab",{name:lang === "he" ? "התקדמות" : "Progress",exact:true}).click();
    assert.equal(await mobile.locator(".health-progress-chart svg").count(),1,"two weigh-ins keep a real trend graph");
    const weightCard = mobile.locator(".health-progress-chart").filter({has:mobile.getByRole("heading",{name:lang === "he" ? "מעקב משקל" : "Weight history",exact:true})});
    assert.match(await weightCard.locator(".health-progress-latest strong").textContent(),/79\.5/,"fractional weigh-ins are not rounded into a different weight");
    assert.equal(await mobile.locator(".health-progress-stats").count(),0,"nutrition-only users do not see workout statistics");
    if(process.env.WELLNESS_SCREENSHOTS_DIR) await mobile.screenshot({path:join(process.env.WELLNESS_SCREENSHOTS_DIR,lang+"-progress-series.png"),animations:"disabled"});

    await mobile.close();
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
        if (screen === "nutrition") {
          assert.deepEqual(await preview.locator(".health-summary [role=progressbar]").evaluateAll((rings) => rings.map((ring)=>Number(ring.getAttribute("aria-valuenow")))),[0,0,0,0],"empty daily rings are empty, never decorative half-filled circles");
        }
        await preview.screenshot({
          path: join(
            process.env.WELLNESS_SCREENSHOTS_DIR,
            `${lang}-${screen}.png`,
          ),
          animations: "disabled",
        });
      }
      await preview.close();
      const daily = await browser.newPage({ viewport: { width: 390, height: 844 } });
      await daily.goto(base + "/?preview=1&daily-populated=1&lang=" + lang);
      await daily.getByRole("tab", { name: lang === "he" ? "היום" : "Today", exact: true }).click();
      await daily.getByRole("heading", { name: lang === "he" ? "הארוחות של היום" : "Your meals today", exact: true }).waitFor();
      await daily.evaluate(async () => { await document.fonts.ready; window.scrollTo(0, 0); });
      const layout = await daily.evaluate(() => {
        const box = (selector) => { const r = document.querySelector(selector).getBoundingClientRect(); return { x:r.x,y:r.y,width:r.width,height:r.height,bottom:r.bottom }; };
        return { diary:box(".health-diary-heading"), card:box(".health-meal-card"), nav:box(".health-bottom-nav"), selected:box(".health-date-wheel [aria-pressed=true]"), viewport:innerWidth, overflow:document.documentElement.scrollWidth>innerWidth+1 };
      });
      assert(layout.diary.bottom < layout.nav.y, "daily meals heading is visible above navigation");
      assert(layout.card.y < layout.nav.y, "first meal appears in the initial phone viewport");
      assert(layout.selected.x >= 0 && layout.selected.x + layout.selected.width <= layout.viewport, "selected calendar date is visible and centered");
      assert(!layout.overflow, "daily layout has no horizontal overflow");
      await daily.screenshot({ path: join(process.env.WELLNESS_SCREENSHOTS_DIR, `${lang}-nutrition-populated.png`), animations:"disabled" });
      await daily.setViewportSize({ width:320,height:740 });
      assert(await daily.evaluate(() => document.documentElement.scrollWidth <= innerWidth+1), "compact daily screen fits a small phone");
      await daily.screenshot({ path: join(process.env.WELLNESS_SCREENSHOTS_DIR, `${lang}-nutrition-small.png`), animations:"disabled" });
      await daily.setViewportSize({ width:390,height:844 });
      await daily.getByRole("button", { name:lang === "he" ? "הוספת ארוחה" : "Add meal",exact:true }).click();
      await daily.getByRole("dialog").waitFor();
      assert.equal(await daily.locator(".meal-action-grid>button").count(),6,"add menu has a balanced grid of six primary actions");
      await daily.screenshot({ path:join(process.env.WELLNESS_SCREENSHOTS_DIR,`${lang}-add-menu.png`),animations:"disabled" });
      await daily.getByRole("button",{name:lang === "he" ? "סגירה" : "Close",exact:true}).click();
      await daily.goto(base+"/?preview=1&daily-populated=1&daily-over=1&lang="+lang);
      await daily.getByRole("tab",{name:lang === "he" ? "היום" : "Today",exact:true}).click();
      await daily.getByText(lang === "he" ? "קלוריות מעל היעד" : "calories over your goal",{exact:true}).waitFor();
      assert.equal((await daily.locator(".health-energy[data-over=true]>div>p").nth(1).innerText()).replace(/\D/g,""),"727","over-goal calories are shown rather than clamped to zero");
      assert.equal(await daily.locator(".health-macro.is-over").count(),2,"only exceeded macro goals are highlighted");
      await daily.screenshot({path:join(process.env.WELLNESS_SCREENSHOTS_DIR,`${lang}-nutrition-over.png`),animations:"disabled"});
      await daily.close();
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
  const tabsBeforePhotoOpen = photo.context().pages().length;
  await photo.getByRole("button", { name: "Open meal and correct recognition", exact: true }).click();
  assert.equal(photo.context().pages().length, tabsBeforePhotoOpen, "thumbnail opens meal corrections, not a raw image tab");
  await photo.getByRole("region", { name: "Correct recognition with text", exact: true }).waitFor();
  const correctionBounds = await photo.getByLabel("What should change?", { exact: true }).boundingBox();
  assert(correctionBounds && correctionBounds.y >= 0 && correctionBounds.y + correctionBounds.height < 844, "free-text correction appears in the first mobile viewport");
  if (process.env.WELLNESS_SCREENSHOTS_DIR) await photo.screenshot({ path: join(process.env.WELLNESS_SCREENSHOTS_DIR, "photo-correction-visible.png"), animations: "disabled" });
  await photo.getByLabel("What should change?").fill("זה דג ולא חזה עוף");
  await photo.evaluate(() => history.replaceState(null, "", "/?photo-test=1&correction-error=1"));
  await photo.getByRole("button", { name: "Update meal", exact: true }).click();
  await photo.getByRole("alert").waitFor();
  assert.equal(await photo.getByLabel("What should change?").inputValue(), "זה דג ולא חזה עוף", "a failed correction retains the personal text");
  assert.equal((await actions(photo)).filter((c) => c.table === "meals").length, 1, "a failed correction does not alter the diary");
  await photo.evaluate(() => history.replaceState(null, "", "/?photo-test=1"));
  await photo.getByRole("button", { name: "Update meal", exact: true }).click();
  await photo.getByText("Meal updated", { exact: true }).waitFor();
  await photo
    .getByRole("dialog")
    .getByRole("heading", { name: "דג", exact: true })
    .waitFor();
  await photo
    .getByRole("list", { name: "Meal ingredients", exact: true })
    .waitFor();
  assert.equal(
    (await actions(photo)).filter((c) => c.table === "meals").length,
    2,
    "correction updates the existing meal",
  );
  assert.equal(
    await photo.evaluate(
      () =>
        window.wellnessFixture.meals().filter((m) => !!m.data.aiEstimate)
          .length,
    ),
    1,
    "correction does not insert another meal",
  );
  assert.equal(
    await photo.evaluate(() => window.wellnessFixture.meals().at(-1).id),
    savedMealId,
    "correction preserves meal identity",
  );
  await photo.getByLabel("What should change?").fill("יש גם מיונז 15 גרם");
  await photo.getByRole("button", { name: "Update meal", exact: true }).click();
  await photo
    .getByRole("list", { name: "Meal ingredients", exact: true })
    .getByText("מיונז", { exact: true })
    .waitFor();
  assert.equal(
    await photo.evaluate(
      () => window.wellnessFixture.meals().at(-1).data.items[1].quantity,
    ),
    15,
    "explicit missing ingredient amount is retained",
  );
  assert.equal(
    await photo.evaluate(() => window.wellnessFixture.meals().at(-1).id),
    savedMealId,
    "adding a missing ingredient updates the same meal",
  );
  const beforePortionAI = (await actions(photo)).filter((c) => c.action === "nutrition" || c.action === "correct_meal").length;
  await photo.getByRole("button", { name: "Update amount: דג", exact: true }).click();
  await photo.getByRole("heading", { name: "Update amount", exact: true }).waitFor();
  assert.equal(await photo.getByRole("region", { name: "Correct recognition with text", exact: true }).count(), 0, "portion editing has a focused screen");
  const portionBounds = await photo.getByLabel("Amount (g)", { exact: true }).boundingBox();
  assert(portionBounds && portionBounds.y > 0 && portionBounds.y + portionBounds.height < 844, "amount input is immediately visible");
  await photo.getByLabel("Amount (g)", { exact: true }).fill("0");
  assert(await photo.getByRole("button", { name: "Update", exact: true }).isDisabled(), "invalid amounts cannot be saved");
  await photo.getByLabel("Amount (g)", { exact: true }).fill("50");
  if (process.env.WELLNESS_SCREENSHOTS_DIR) await photo.screenshot({ path: join(process.env.WELLNESS_SCREENSHOTS_DIR, "focused-portion-editing.png"), animations: "disabled" });
  await photo.getByText("Weight range or save product", { exact: true }).click();
  await photo.getByLabel("Up to (g)", { exact: true }).fill("60");
  await photo.getByLabel("Save this weight for one unit of a specific product", { exact: true }).check();
  await photo.getByLabel("Specific product name", { exact: true }).fill("Test fish product");
  await photo.getByRole("button", { name: "Update", exact: true }).click();
  await photo.getByRole("button", { name: "Update amount: Test fish product", exact: true }).waitFor();
  const remembered = await photo.evaluate(() => ({ food: window.wellnessFixture.foods().at(-1), meal: window.wellnessFixture.meals().at(-1) }));
  assert.deepEqual(remembered.food.data.unitWeight, { low: 50, high: 60 });
  assert.equal(remembered.food.data.source, "ai", "confirming grams does not verify AI nutrient values");
  assert.equal(remembered.meal.data.items[0].quantity, 55);
  assert.deepEqual(remembered.meal.data.items[0].quantityRange, { low: 50, high: 60 });
  assert.equal(remembered.meal.data.items[1].quantity, 15, "other ingredients are never scaled to fit the anchor");
  await photo.getByRole("button", { name: "Update amount: Test fish product", exact: true }).click();
  await photo.getByText("Choose a saved product", { exact: true }).click();
  await photo.getByLabel("Saved product", { exact: true }).selectOption(remembered.food.id);
  await photo.getByLabel("Number of units", { exact: true }).fill("2");
  await photo.getByRole("button", { name: "Update", exact: true }).click();
  await photo.getByLabel("Number of units", { exact: true }).waitFor({ state: "hidden" });
  assert.equal(await photo.evaluate(() => window.wellnessFixture.meals().at(-1).data.items[0].quantity), 110);
  assert.equal((await actions(photo)).filter((c) => c.action === "nutrition" || c.action === "correct_meal").length, beforePortionAI, "saved-unit corrections never call AI");
  const beforePortionRetry = (await actions(photo)).filter((c) => c.table === "meals").length;
  await photo.getByRole("button", { name: "Update amount: Test fish product", exact: true }).click();
  await photo.getByLabel("Amount (g)", { exact: true }).fill("110");
  await photo.evaluate(() => history.replaceState(null, "", "/?photo-test=1&portion-cache-failure=1"));
  await photo.getByRole("button", { name: "Update", exact: true }).click();
  await photo.getByRole("button", { name: "Saving…", exact: true }).waitFor();
  assert(await photo.getByLabel("Amount (g)", { exact: true }).isDisabled(), "store updates do not remount/reset an in-flight editor");
  await photo.getByRole("heading", { name: "Update amount", exact: true }).waitFor({ state: "hidden" });
  assert.equal((await actions(photo)).filter((c) => c.table === "meals").length, beforePortionRetry + 1, "accepted portion save is not duplicated after cache failure");
  await photo.evaluate(() => history.replaceState(null, "", "/?photo-test=1"));
  await photo.getByRole("button", { name: "Update amount: Test fish product", exact: true }).click();
  await photo.getByLabel("Amount (g)", { exact: true }).fill("90");
  await photo.evaluate((id) => window.wellnessFixture.advanceMealVersion(id), savedMealId);
  assert.equal(await photo.getByLabel("Amount (g)", { exact: true }).inputValue(), "90", "concurrent update does not discard the current draft");
  await photo.getByRole("button", { name: "Update", exact: true }).click();
  await photo.getByText("This record changed. Reopen it before saving again.", { exact: true }).waitFor();
  assert.equal(await photo.evaluate(() => window.wellnessFixture.meals().at(-1).data.items[0].quantity), 110, "stale portion edit cannot overwrite the newer version");
  await photo.getByRole("button", { name: "Cancel", exact: true }).click();
  await photo.getByRole("button", { name: "Close", exact: true }).click();
  await photo.getByText("My foods & favorites", { exact: true }).click();
  await photo.getByRole("button", { name: "50–60 g · per unit", exact: true }).click();
  await photo.getByLabel("From (g)", { exact: true }).fill("55");
  await photo.getByLabel("To (g)", { exact: true }).fill("65");
  await photo.getByRole("button", { name: "Save", exact: true }).click();
  await photo.getByRole("button", { name: "55–65 g · per unit", exact: true }).waitFor();
  assert.equal(await photo.evaluate(() => window.wellnessFixture.meals().at(-1).data.items[0].quantity), 110, "editing a product never rewrites logged meals");
  await photo.getByRole("button", { name: "Correct recognition", exact: true }).click();
  const beforeManualEdits = await photo.evaluate(() => structuredClone(window.wellnessFixture.meals().at(-1)));
  const aiCallsBeforeManualEdits = (await actions(photo)).filter((c) => ["nutrition", "correct_meal"].includes(c.action)).length;
  await photo.getByRole("button", { name: "Remove ingredient: מיונז", exact: true }).click();
  await photo.getByText("Ingredient removed", { exact: true }).waitFor();
  assert.equal(await photo.evaluate(() => window.wellnessFixture.meals().at(-1).data.items.length), 1);
  assert.equal(await photo.getByRole("button", { name: /^Remove ingredient:/ }).count(), 0, "last ingredient cannot leave an invalid empty meal");
  await photo.getByRole("button", { name: "Undo removal", exact: true }).click();
  await photo.getByText("Ingredient restored", { exact: true }).waitFor();
  assert.deepEqual(await photo.evaluate(() => window.wellnessFixture.meals().at(-1).data.items), beforeManualEdits.data.items, "undo restores exact ingredient snapshots and amounts");
  await photo.getByRole("button", { name: "Add ingredient", exact: true }).click();
  await photo.getByRole("heading", { name: "Add an ingredient to this meal", exact: true }).waitFor();
  await photo.getByRole("button", { name: "Barcode", exact: true }).click();
  await photo.getByLabel("Barcode", { exact: true }).fill("12345678");
  await photo.getByRole("button", { name: "Look up", exact: true }).click();
  await photo.getByRole("button", { name: /Synthetic packaged food/ }).click();
  await photo.getByLabel("Amount eaten (g)", { exact: true }).fill("25");
  await photo.getByRole("button", { name: "Add food", exact: true }).click();
  await photo.getByText("Ingredient added", { exact: true }).waitFor();
  const manuallyEdited = await photo.evaluate(() => window.wellnessFixture.meals().at(-1));
  assert.equal(manuallyEdited.id, savedMealId, "manual ingredient edits update the same diary meal");
  assert.equal(manuallyEdited.data.items.length, 3);
  assert.deepEqual(manuallyEdited.data.items.slice(0, 2), beforeManualEdits.data.items, "adding a food leaves the existing nutrients, units and portions intact");
  assert.equal(manuallyEdited.data.items[2].quantity, 25);
  assert.equal(manuallyEdited.data.items[2].food.source, "openfoodfacts");
  assert.equal((await actions(photo)).filter((c) => ["nutrition", "correct_meal"].includes(c.action)).length, aiCallsBeforeManualEdits, "manual corrections do not use AI");
  await photo.getByRole("button", { name: "Save to favorites", exact: true }).click();
  await photo.getByText("Saved to favorites", { exact: true }).waitFor();
  assert.deepEqual(await photo.evaluate(() => window.wellnessFixture.meals().at(-1).data.items), manuallyEdited.data.items, "header bookmark preserves corrected ingredients");
  await photo.getByRole("button", { name: "Remove from favorites", exact: true }).click();
  await photo.getByText("Removed from favorites", { exact: true }).waitFor();
  await photo.close();
  for (const scenario of ["photo-empty", "photo-retry", "save-retry"]) {
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
      scenario === "save-retry" ? 1 : 0,
      "failed or empty analysis does not save a meal",
    );
    assert.equal(
      await p.evaluate(
        () =>
          window.wellnessFixture.meals().filter((m) => !!m.data.aiEstimate)
            .length,
      ),
      0,
      "failed attempt creates no diary row",
    );
    if (scenario === "save-retry")
      await p
        .getByText(
          "Analysis succeeded, but saving failed. Retry without analyzing the photo again.",
          { exact: true },
        )
        .waitFor();
    if (scenario === "photo-empty") {
      await p
        .getByText("No food identified. Add a short description or choose another photo.", {
          exact: true,
        })
        .waitFor();
      assert.equal(
        await p.getByRole("button", { name: "Retry", exact: true }).count(),
        0,
        "no repeat quota spend on the same empty result",
      );
      const withHint = p.getByRole("button", { name: "Analyze with description", exact: true });
      assert(await withHint.isDisabled(), "empty clarification cannot repeat an unchanged empty analysis");
      await p.getByLabel("What's in the photo?", { exact: true }).fill("טורטייה עם עוף וחסה");
      if (process.env.WELLNESS_SCREENSHOTS_DIR) await p.screenshot({ path: join(process.env.WELLNESS_SCREENSHOTS_DIR, "photo-empty-hint.png") });
      await p.evaluate(() => history.replaceState(null, "", "/?photo-empty=1&hint-retry=1"));
      await withHint.click();
      await p.getByRole("button", { name: "Retry", exact: true }).waitFor();
      await p.getByRole("button", { name: "Retry", exact: true }).click();
      await p.getByRole("dialog").waitFor({ state: "hidden" });
      const hintRequests = (await actions(p)).filter((c) => c.action === "nutrition");
      assert.equal(hintRequests.length, 3, "empty analysis, clarified analysis and its transport retry");
      assert.notEqual(hintRequests[0].requestId, hintRequests[1].requestId, "changed description starts a fresh analysis");
      assert.equal(hintRequests[1].requestId, hintRequests[2].requestId, "transport retry keeps the clarified analysis ID");
      assert.equal(hintRequests[1].description, "טורטייה עם עוף וחסה");
      assert.equal(hintRequests[2].description, hintRequests[1].description);
      assert.equal(hintRequests[1].imagePath, hintRequests[0].imagePath, "clarification reuses the original private upload");
      assert.equal((await actions(p)).filter((c) => c.action === "upload_photo").length, 1);
      assert.equal((await actions(p)).filter((c) => c.table === "meals").length, 1, "clarified success saves one meal automatically");
    } else {
      await p.getByRole("button", { name: "Retry", exact: true }).click();
      await p.getByRole("dialog").waitFor({ state: "hidden" });
      assert.equal(
        (await actions(p)).filter((c) => c.table === "meals").length,
        scenario === "save-retry" ? 2 : 1,
        "retry saves exactly one meal",
      );
    }
    if (scenario === "save-retry")
      assert.equal(
        (await actions(p)).filter((c) => c.action === "nutrition").length,
        1,
        "retry after save failure reuses the completed estimate",
      );
    await p.close();
  }
  const recovery = await browser.newPage({
    viewport: { width: 390, height: 844 },
  });
  await recovery.goto(base + "/?capability-retry=1");
  await recovery
    .getByRole("button", { name: "Plan with AI", exact: true })
    .click();
  await recovery
    .getByRole("button", { name: "Check again", exact: true })
    .first()
    .click();
  await recovery.waitForFunction(() =>
    [...document.querySelectorAll("button")].some(
      (b) => b.textContent === "Create program" && !b.disabled,
    ),
  );
  assert.equal(
    (await actions(recovery)).filter((c) => c.action === "capabilities").length,
    2,
    "all AI consumers share one retried availability request",
  );
  await recovery.close();
  for (const language of ["he", "en"]) {
    const isHebrew = language === "he";
    const progress = await browser.newPage({
      viewport: { width: 390, height: 844 },
    });
    await progress.goto(base + "/?photo-progress=1&lang=" + language);
    await progress
      .getByRole("button", {
        name: isHebrew ? "הוספת ארוחה" : "Add meal",
        exact: true,
      })
      .click();
    await progress
      .getByRole("button", {
        name: isHebrew ? "צלם ארוחה" : "Photograph a meal",
        exact: true,
      })
      .click();
    await progress.waitForFunction(
      () => document.querySelector("video")?.videoWidth > 0,
    );
    await progress
      .getByRole("button", {
        name: isHebrew ? "צילום" : "Take photo",
        exact: true,
      })
      .click();
    await progress
      .getByAltText(isHebrew ? "הארוחה שצולמה" : "Captured meal", {
        exact: true,
      })
      .waitFor();
    await progress.waitForFunction(() =>
      [...document.querySelector("video").srcObject.getTracks()].every(
        (t) => t.readyState === "ended",
      ),
    );
    await progress
      .getByRole("progressbar", {
        name: isHebrew ? "פענוח הארוחה" : "Meal analysis",
        exact: true,
      })
      .waitFor();
    assert.equal(
      await progress.getByRole("progressbar").getAttribute("aria-valuenow"),
      null,
      "analysis progress is not a fabricated percentage",
    );
    await progress
      .getByText(
        isHebrew ? "מזהים מרכיבים וכמויות…" : "Identifying foods and portions…",
        { exact: true },
      )
      .waitFor();
    if (process.env.WELLNESS_SCREENSHOTS_DIR)
      await progress.screenshot({
        path: join(
          process.env.WELLNESS_SCREENSHOTS_DIR,
          language + "-meal-processing.png",
        ),
        animations: "disabled",
      });
    await progress.getByRole("dialog").waitFor({ state: "hidden" });
    await progress
      .getByRole("button", { name: "אורז לבן מבושל", exact: true })
      .click();
    if (process.env.WELLNESS_SCREENSHOTS_DIR)
      await progress.screenshot({
        path: join(
          process.env.WELLNESS_SCREENSHOTS_DIR,
          language + "-meal-ingredients.png",
        ),
        animations: "disabled",
      });
    await progress.close();
  }
  const framing = await browser.newPage({
    viewport: { width: 390, height: 844 },
  });
  await framing.goto(base + "/?photo-progress=1");
  const preserved = await framing.evaluate(async () => {
    const results = [];
    for (const [w, h] of [
      [3000, 1000],
      [1000, 3000],
    ]) {
      const c = document.createElement("canvas");
      c.width = w;
      c.height = h;
      const ctx = c.getContext("2d");
      ctx.fillStyle = "#f00000";
      ctx.fillRect(0, 0, w / 3, h);
      ctx.fillStyle = "#00c000";
      ctx.fillRect(w / 3, 0, w / 3, h);
      ctx.fillStyle = "#0000f0";
      ctx.fillRect((w * 2) / 3, 0, w / 3, h);
      const raw = await new Promise((resolve) =>
        c.toBlob(resolve, "image/png"),
      );
      const blob = await window.wellnessFixture.prepareImage(
        new File([raw], "frame.png", { type: "image/png" }),
      );
      const bitmap = await createImageBitmap(blob),
        out = document.createElement("canvas");
      out.width = bitmap.width;
      out.height = bitmap.height;
      const draw = out.getContext("2d");
      draw.drawImage(bitmap, 0, 0);
      bitmap.close();
      results.push({
        w: out.width,
        h: out.height,
        left: [...draw.getImageData(5, Math.floor(out.height / 2), 1, 1).data],
        right: [
          ...draw.getImageData(out.width - 6, Math.floor(out.height / 2), 1, 1)
            .data,
        ],
      });
    }
    return results;
  });
  assert.deepEqual(
    preserved.map((r) => [r.w, r.h]),
    [
      [1800, 600],
      [600, 1800],
    ],
    "upload resizing preserves wide and tall aspect ratios",
  );
  for (const r of preserved) {
    assert(
      r.left[0] > 180 && r.left[2] < 60 && r.right[2] > 180 && r.right[0] < 60,
      "both original photo edges survive upload preparation",
    );
  }
  await framing.getByRole("button", { name: "Add meal", exact: true }).click();
  await framing
    .getByRole("button", { name: "Photograph a meal", exact: true })
    .click();
  const wide = await framing.evaluate(() => {
    const c = document.createElement("canvas");
    c.width = 1200;
    c.height = 400;
    const x = c.getContext("2d");
    x.fillStyle = "#eb4238";
    x.fillRect(0, 0, 400, 400);
    x.fillStyle = "#59c36a";
    x.fillRect(400, 0, 400, 400);
    x.fillStyle = "#3988ee";
    x.fillRect(800, 0, 400, 400);
    return c.toDataURL("image/png").split(",")[1];
  });
  await framing.locator('input[type="file"]').setInputFiles({
    name: "wide.png",
    mimeType: "image/png",
    buffer: Buffer.from(wide, "base64"),
  });
  await framing.getByAltText("Captured meal", { exact: true }).waitFor();
  assert.equal(
    await framing
      .getByAltText("Captured meal", { exact: true })
      .evaluate((el) => getComputedStyle(el).objectFit),
    "contain",
    "the displayed whole photo matches the uploaded frame",
  );
  if (process.env.WELLNESS_SCREENSHOTS_DIR)
    await framing.screenshot({
      path: join(
        process.env.WELLNESS_SCREENSHOTS_DIR,
        "whole-landscape-photo.png",
      ),
      animations: "disabled",
    });
  await framing.getByRole("dialog").waitFor({ state: "hidden" });
  await framing.close();
  const noAI = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await noAI.goto(base + "/?ai-off=1");
  await noAI.getByRole("button", { name: "Add meal", exact: true }).click();
  await noAI
    .getByRole("button", { name: "Packaged product", exact: true })
    .click();
  await noAI.getByLabel("Barcode scanner", { exact: true }).waitFor();
  assert.equal(
    await noAI
      .getByRole("group", { name: "Entry method", exact: true })
      .count(),
    0,
    "packaged product skips input method selection",
  );
  assert.equal(
    await noAI.getByText("Meal details & date", { exact: true }).count(),
    0,
    "packaged product starts without meal metadata",
  );
  assert.equal(
    await noAI
      .getByRole("button", { name: "Save to diary", exact: true })
      .count(),
    0,
    "no empty diary save before product selection",
  );
  if (process.env.WELLNESS_SCREENSHOTS_DIR)
    await noAI.screenshot({
      path: join(process.env.WELLNESS_SCREENSHOTS_DIR, "direct-product.png"),
      animations: "disabled",
    });
  await noAI.getByLabel("Product barcode", { exact: true }).fill("12345678");
  assert.equal(
    await noAI.getByLabel("Barcode scanner", { exact: true }).count(),
    0,
    "typing releases the camera",
  );
  const lookup = noAI.getByRole("button", {
    name: "Find product",
    exact: true,
  });
  assert(await lookup.isEnabled(), "barcode lookup works with AI disabled");
  await lookup.click();
  await noAI.getByText("Synthetic packaged food", { exact: true }).waitFor();
  await noAI.getByLabel("Amount eaten (g)", { exact: true }).fill("75");
  await noAI.getByLabel("I checked that the product, unit and values match the package", { exact: true }).check();
  await noAI.getByRole("button", { name: "Add to meal", exact: true }).click();
  await noAI.getByRole("button", { name: "Save to diary", exact: true }).click();
  assert.equal(await noAI.evaluate(() => window.wellnessFixture.meals().at(-1).data.items[0].quantity), 75);
  assert(
    !(await actions(noAI)).some((c) => c.action === "nutrition"),
    "disabled AI is never used for labels",
  );
  await noAI.close();

  // The barcode route inside food search must also ask for quantity before adding.
  const foodBarcode = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await foodBarcode.goto(base + "/?ai-disabled=1");
  await foodBarcode.getByRole("button", { name: "Add meal", exact: true }).click();
  await foodBarcode.getByRole("button", { name: "Food database", exact: true }).click();
  await foodBarcode.getByRole("button", { name: "Barcode", exact: true }).click();
  await foodBarcode.getByLabel("Barcode", { exact: true }).fill("12345678");
  await foodBarcode.getByRole("button", { name: "Look up", exact: true }).click();
  await foodBarcode.getByRole("button", { name: /Synthetic packaged food/ }).click();
  const searchedAmount = foodBarcode.getByRole("region", { name: "Product amount", exact: true });
  await searchedAmount.getByLabel("Amount eaten (g)", { exact: true }).fill("25");
  await foodBarcode.getByRole("button", { name: "Add food", exact: true }).click();
  await foodBarcode.getByRole("button", { name: "Save to diary", exact: true }).click();
  assert.equal(await foodBarcode.evaluate(() => window.wellnessFixture.meals().at(-1).data.items[0].quantity), 25);
  assert(!(await actions(foodBarcode)).some((c) => c.action === "nutrition"), "food-search barcode quantity never calls AI");
  const originalRepeat = await foodBarcode.evaluate(() => structuredClone(window.wellnessFixture.meals().at(-1)));
  const countBeforeRepeat = await foodBarcode.evaluate(() => window.wellnessFixture.meals().length);
  await foodBarcode.getByRole("button", { name: "Add meal", exact: true }).click();
  await foodBarcode.getByRole("button", { name: "Previous meal", exact: true }).click();
  await foodBarcode.getByRole("heading", { name: "Previous meals", exact: true }).waitFor();
  await foodBarcode.getByLabel("Search meals", { exact: true }).fill("missing meal");
  await foodBarcode.getByText("No previous meals found", { exact: true }).waitFor();
  await foodBarcode.getByLabel("Search meals", { exact: true }).fill("Synthetic packaged");
  if (process.env.WELLNESS_SCREENSHOTS_DIR) await foodBarcode.screenshot({ path: join(process.env.WELLNESS_SCREENSHOTS_DIR, "previous-meals.png") });
  await foodBarcode.getByRole("button", { name: "Add again: Synthetic packaged food", exact: true }).click();
  await foodBarcode.getByRole("heading", { name: "Previous meals", exact: true }).waitFor({ state: "hidden" });
  const afterRepeat = await foodBarcode.evaluate(() => structuredClone(window.wellnessFixture.meals()));
  assert.equal(afterRepeat.length, countBeforeRepeat + 1, "one repeated meal is saved");
  assert.deepEqual(afterRepeat.find((m) => m.id === originalRepeat.id), originalRepeat, "repetition leaves the original diary record unchanged");
  const repeated = afterRepeat.at(-1);
  assert.notEqual(repeated.id, originalRepeat.id);
  assert.notEqual(repeated.data.items[0].id, originalRepeat.data.items[0].id);
  assert.deepEqual({ ...repeated.data.items[0], id: originalRepeat.data.items[0].id }, originalRepeat.data.items[0]);
  assert.equal(repeated.data.imagePath, null);
  assert.equal(repeated.data.aiEstimate, undefined);
  assert(!(await actions(foodBarcode)).some((c) => c.action === "nutrition" || c.action === "correct_meal"), "repeat meals do not call AI");
  await foodBarcode.getByRole("button", { name: "Add meal", exact: true }).click();
  await foodBarcode.getByRole("button", { name: "Previous meal", exact: true }).click();
  await foodBarcode.getByRole("button", { name: "Favorites", exact: true }).click();
  await foodBarcode.getByText("Bookmark a meal to find it here", { exact: true }).waitFor();
  await foodBarcode.getByRole("button", { name: "Recent", exact: true }).click();
  await foodBarcode.getByRole("button", { name: "Save to favorites: Synthetic packaged food", exact: true }).first().click();
  const favoriteRow = await foodBarcode.evaluate(() => structuredClone(window.wellnessFixture.meals().find((m) => m.data.favorite)));
  assert.deepEqual(favoriteRow.data.items, originalRepeat.data.items.map((item, index) => ({ ...item, id: favoriteRow.data.items[index].id })), "bookmark preserves exact food amounts and values");
  await foodBarcode.getByRole("dialog").getByRole("button", { name: "Close", exact: true }).click();
  await foodBarcode.getByRole("button", { name: "Add meal", exact: true }).click();
  await foodBarcode.getByRole("button", { name: "Previous meal", exact: true }).click();
  await foodBarcode.getByRole("button", { name: "Favorites", exact: true }).click();
  if (process.env.WELLNESS_SCREENSHOTS_DIR) await foodBarcode.screenshot({ path: join(process.env.WELLNESS_SCREENSHOTS_DIR, "favorite-meals.png") });
  await foodBarcode.getByRole("button", { name: "Add again: Synthetic packaged food", exact: true }).click();
  await foodBarcode.getByRole("heading", { name: "Favorite meals", exact: true }).waitFor({ state: "hidden" });
  const favoriteCopies = await foodBarcode.evaluate(() => structuredClone(window.wellnessFixture.meals()));
  assert.equal(favoriteCopies.length, countBeforeRepeat + 2);
  assert.equal(favoriteCopies.filter((m) => m.data.favorite).length, 1, "copies do not create extra favorites");
  assert.deepEqual(favoriteCopies.find((m) => m.id === favoriteRow.id), favoriteRow, "favorite source is unchanged by reuse");
  await foodBarcode.getByRole("button", { name: "Add meal", exact: true }).click();
  await foodBarcode.getByRole("button", { name: "Previous meal", exact: true }).click();
  await foodBarcode.getByRole("button", { name: "Favorites", exact: true }).click();
  await foodBarcode.getByRole("button", { name: "Remove from favorites: Synthetic packaged food", exact: true }).click();
  await foodBarcode.getByText("Bookmark a meal to find it here", { exact: true }).waitFor();
  assert.equal(await foodBarcode.evaluate(() => window.wellnessFixture.meals().length), favoriteCopies.length, "unfavorite never deletes diary history");
  assert(!(await actions(foodBarcode)).some((c) => c.action === "nutrition" || c.action === "correct_meal"), "favorites work with AI disabled");
  await foodBarcode.close();

  console.log(
    "PASS: Hebrew/English mobile proposal approval, food estimate confirmation, non-AI barcode/printed-label flow with AI disabled, separate training consent, per-example approval/revocation, automatic photo save and saved-meal correction, adult gate, chat follow-ups/history/deletion, opt-in context and escaped model text. Synthetic services; live model not tested.",
  );
} finally {
  await browser?.close();
  await new Promise((r) => (server ? server.close(r) : r()));
  await rm(temp, { recursive: true, force: true });
}

// Run after flutter build web and starting a local server.
// PLAYWRIGHT_MODULE may point to a temporary Playwright install.
// Set ESP32_IP and ESP32_PIN to also send a real notification; otherwise local-only.
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

(async () => {
  fs.mkdirSync('build/ux', {recursive: true});
  const browser = await chromium.launch({headless: true});
  const errors = [];
  let activePage;
  try {
    for (const width of [375, 768, 1024, 1440]) {
      const context = await browser.newContext({viewport: {width, height: 900}});
      const page = await context.newPage();
      activePage = page;
      page.setDefaultTimeout(12000);
      const destination = name => page.getByRole('tab', {name, exact: true})
        .or(page.getByRole('button', {name: new RegExp(`^${name}\\s+Tab \\d of 3$`)}));
      page.on('pageerror', error => errors.push(error.message));
      // Flutter replaces the semantics proxy on focus; type into the real editor.
      async function enter(name, value) {
        await page.getByRole('textbox', {name}).click();
        await page.waitForFunction(() => ['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName));
        await page.keyboard.press('ControlOrMeta+A');
        await page.keyboard.insertText(value);
        await page.keyboard.press('Tab');
      }
      await page.goto(process.env.PREVIEW_URL || 'http://127.0.0.1:8080');
      await page.locator('flt-semantics-placeholder').evaluate(element => element.click());
      await destination('Settings').waitFor();
      await page.screenshot({path: `build/ux/navigation-${width}.png`});
      await destination('Content').click();
      await page.getByRole('button', {name: 'Add notification', exact: true}).waitFor();
      await page.screenshot({path: `build/ux/content-${width}.png`});
      await destination('Settings').click();
      await page.getByRole('checkbox', {name: 'Bluetooth', exact: true}).waitFor();
      await page.screenshot({path: `build/ux/settings-${width}.png`});
      if (width === 375) {
        if (process.env.ESP32_IP) {
          await page.getByRole('checkbox', {name: 'Wi-Fi', exact: true}).click();
          assert.match(process.env.ESP32_PIN || '', /^\d{6}$/, 'Set ESP32_PIN for the live device test');
          await enter('ESP32 pairing PIN', process.env.ESP32_PIN);
          await enter('ESP32 IP address', process.env.ESP32_IP);
          const health = page.waitForResponse(response => response.url().endsWith('/api/health'));
          await page.getByRole('button', {name: 'Save and connect', exact: true}).click();
          assert.equal((await health).status(), 200);
          await page.getByRole('button', {name: 'Save and connect', exact: true}).waitFor();
          await page.screenshot({path: 'build/ux/connected-375.png'});
        }
        await destination('Content').click();
        await page.getByRole('button', {name: 'Add notification', exact: true}).click();
        await enter('Title', 'Web delivery test');
        await enter('Content', 'Nguyễn Huệ → 250 m');
        await page.getByRole('button', {name: 'Save', exact: true}).click();
        await page.getByRole('button', {name: 'Content options'}).waitFor();
        if (process.env.ESP32_IP) {
          await page.getByRole('button', {name: 'Content options'}).click();
          const delivery = page.waitForResponse(response => response.url().endsWith('/api/command'));
          await page.getByRole('menuitem', {name: 'Send to display'}).click();
          const result = await delivery;
          assert.equal(result.status(), 200);
          assert.equal((await result.json()).ok, true);
          const sent = result.request().postDataJSON();
          assert.equal(sent.body, 'Nguyen Hue > 250 m');
          await page.getByText('ESP32 confirmed delivery.', {exact: true}).last().waitFor();
        }
        await page.screenshot({path: 'build/ux/content-saved-375.png'});
        await page.getByRole('button', {name: 'Content options'}).click();
        await page.getByRole('menuitem', {name: 'Edit', exact: true}).click();
        await enter('Title', 'Edited reminder');
        await enter('Content', 'Edited locally');
        await page.getByRole('button', {name: 'Save', exact: true}).click();
        await page.getByRole('group', {name: /^Edited reminder/}).waitFor();
        await destination('Settings').click();
        await page.getByRole('button', {name: /Privacy and data/}).click();
        const clear = page.getByRole('button', {name: 'Delete saved data', exact: true});
        await clear.scrollIntoViewIfNeeded();
        await page.screenshot({path: 'build/ux/privacy-375.png'});
        await clear.click();
        await page.getByRole('button', {name: 'Cancel', exact: true}).click();
        await destination('Content').click();
        await page.getByRole('group', {name: /^Edited reminder/}).waitFor();
        await destination('Settings').click();
        await clear.click();
        await page.getByRole('button', {name: 'Delete data', exact: true}).click();
        await page.getByText('Saved data deleted. GPS speed and sharing are off.', {exact: true}).waitFor();
        assert.deepEqual(await page.evaluate(() => Object.keys(localStorage)
          .filter(key => /esp32-(?:navride|monitor)\.snapshot/.test(key))), []);
        await destination('Content').click();
        await page.getByText(/No notifications yet/).waitFor();
        await page.reload();
        await page.locator('flt-semantics-placeholder').evaluate(element => element.click());
        await destination('Content').click();
        await page.getByText(/No notifications yet/).waitFor();
        console.log('PASS edit, cancel deletion and delete saved data');
      }
      await context.close();
      console.log(`PASS web layout ${width}px`);
    }
    assert.deepEqual(errors, []);
    console.log('PASS browser flows', process.env.ESP32_IP ? 'including live ESP32 delivery' : '(local only)');
  } catch (error) {
    if (activePage && !activePage.isClosed()) {
      await activePage.screenshot({path: 'build/ux/failure.png'});
      fs.writeFileSync('build/ux/failure-aria.txt', await activePage.locator('body').ariaSnapshot());
    }
    throw error;
  } finally {
    await browser.close();
  }
})().catch(error => {console.error(error); process.exitCode = 1;});

// Checks the web Work Checker (docs/parchment-web.js) against the same cases as
// Tools/test_work_checker.swift, so the two engines keep giving the same verdicts.
//
//   node Tools/test_web_checker.js
const assert = require("assert");
const path = require("path");
const { WorkChecker } = require(path.join(__dirname, "..", "docs", "parchment-web.js"));

// The verdict for the last line of a page: "verified", "needsAttention", "evaluated" or "tracking".
const check = (...lines) => WorkChecker.checkLines(lines, lines.length - 1).pop().feedback;
const kinds = (...lines) => WorkChecker.checkLines(lines, -1).map((a) => a.feedback.kind);

const verified = [
  ["14 * 3 = 42"], ["12 * 3 + 4 = 36 + 4 = 40"],
  // precedence, rounded answers, thousands separators, mixed numbers
  ["-3^2 = -9"], ["2^3^2 = 512"], ["2 * -3^2 = -18"], ["(-3)^2 = 9"],
  ["22 / 7 = 3.14"], ["sqrt(2) = 1.414"], ["2 * pi = 6.28"], ["2/3 = 0.67"], ["2/3 = 0.66"],
  ["1,000 + 500 = 1,500"], ["1 1/2 + 1/2 = 2"], ["2 * 1 1/2 = 3"],
  // trig in degrees, percentages, factorials, units
  ["sin(30) + sqrt(144) = 12.5"], ["sin(90) = 1"], ["sin(pi/2) = 1"], ["15% of 80 = 12"], ["5! = 120"],
  ["5 m + 30 cm = 5.3 m"], ["50 cm + 50 cm = 100"], ["2 km = 2000 m"], ["1.5 hr = 90 min"],
  // algebra steps
  ["2x + 6 = 14", "2x = 8"], ["2x + 6 = 14", "x = 4"], ["(x + 2)(x + 3) = x^2 + 5x + 6"],
  // two solutions
  ["x^2 = 16", "x = 4"], ["x^2 = 16", "x = -4"], ["x^2 = 16", "x = 4 or x = -4"],
  ["x^2 = 16", "x = ±4"], ["x^2 = 16", "x = -4, 4"], ["x^2 + 1 = 0"]
];
for (const lines of verified) {
  const fb = check(...lines);
  assert.strictEqual(fb.kind, "verified", `${lines.join(" → ")} should be verified, got: ${fb.message}`);
}

const slips = [
  [["14 * 3 = 48"], "14 * 3 = 42"],
  [["7 / 2 = 3"], "7 / 2 = 3.5"],
  [["2/3 = 0.68"], "2/3 = 0.6667"],
  [["12.5 * 2 = 25.4"], "12.5 * 2 = 25"],
  [["2 + 2 = 5 = 5"], "2 + 2 = 4 = 4"],
  [["2 km = 200 m"], "2 km = 2000 m"],
  [["2x + 6 = 14", "2x = 20"], "2x = 8"],
  [["2x + 6 = 14", "x = 5"], "x = 4"],
  [["x^2 = 16", "x = 5"], "x = -4 or x = 4"],
  [["x^2 = 16", "x = 4 or x = 5"], "x = -4 or x = 4"],
  [["2(x + 3) = 2x + 9"], "2(x + 3) = 2x + 6"],
  [["We could of finished earlier."], "We could have finished earlier."],
  [["In order to win, we practice."], "To win, we practice."]
];
for (const [lines, fix] of slips) {
  const fb = check(...lines);
  assert.strictEqual(fb.kind, "needsAttention", `${lines.join(" → ")} should be flagged, got: ${fb.message}`);
  assert.strictEqual(fb.replacementText, fix, `${lines.join(" → ")} should be fixed to "${fix}"`);
  // Applying the fix must leave a line the checker accepts.
  const fixed = check(...lines.slice(0, -1), fix);
  assert.notStrictEqual(fixed.kind, "needsAttention", `the fix "${fix}" is flagged again: ${fixed.message}`);
}

// Not enough to judge: must not be flagged.
for (const line of ["5m = 500", "2 km = 2000", "E = mc^2", "Date = 11/20/2026", "100 - 15% = 85"]) {
  assert.notStrictEqual(check(line).kind, "needsAttention", `${line} should not be flagged`);
}

// A whole page: one slip doesn't cascade, and a new problem starts fresh.
assert.deepStrictEqual(kinds("2x + 6 = 14", "2x = 20", "x = 4"), ["verified", "needsAttention", "verified"]);
assert.deepStrictEqual(kinds("2x + 6 = 14", "x = 4", "3x = 9", "x = 3"), ["verified", "verified", "verified", "verified"]);
assert.deepStrictEqual(kinds("x^2 = 16", "x = 4", "x = -4"), ["verified", "verified", "verified"]);
assert.deepStrictEqual(kinds("2x = 8", "Now the next question", "5x = 10"), ["verified", "tracking", "verified"]);

// Answers ready to insert.
assert.strictEqual(check("24 * 15 =").replacementText, "24 * 15 = 360");
assert.strictEqual(check("5 m + 30 cm").replacementText, "5 m + 30 cm = 5.3 m");
assert.strictEqual(check("2(x + 3) =").replacementText, "2(x + 3) = 2x + 6");

// Active Recall: a style note in the rewrite is not a math slip.
const recall = WorkChecker.compareRecall(
  "Mitosis has four phases: prophase, metaphase, anaphase, telophase. 2x + 6 = 14, x = 4",
  "We could of said mitosis phases: prophase, metaphase, anaphase. 2x + 6 = 14, x = 4"
);
assert.ok(recall.matchedTerms.includes("prophase") && recall.missedTerms.includes("telophase"));
assert.strictEqual(recall.mathSlips.length, 0);

console.log(`✓ Web Work Checker: ${verified.length + slips.length} line checks, page context, answers and recall all pass.`);

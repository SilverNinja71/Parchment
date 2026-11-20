// Parchment Web Studio & Live Work Follower Engine
// 100% client-side, offline-first JavaScript port of Parchment/Editor/WorkChecker.swift
// Adheres strictly to Parchment/App/Style.swift and CONTRIBUTING.md.

(function () {
  "use strict";

  // ============================================================================
  // 1. Symbolic, Numerical & Scientific Algebraic Engine (Port of AlgebraicEngine)
  // ============================================================================
  const AlgebraicEngine = {
    detectVariable(text) {
      let cleaned = text
        .replace(/\$+/g, " ")
        .replace(/\\(frac|sqrt|cbrt|cdot|times|div|left|right|sin|cos|tan|asin|acos|atan|ln|log|exp|abs|pi)/gi, " ")
        .replace(/\b(sqrt|cbrt|sin|cos|tan|asin|acos|atan|ln|log|exp|abs|pi|mod|of|in|to)\b/gi, " ");
      cleaned = cleaned.replace(/(?<=[0-9)])\s+[xX]\s+(?=[0-9(])/g, " * ");
      const preferred = ["x", "y", "z", "t", "n", "a", "b", "c", "k", "m", "r", "s", "u", "v", "w"];
      const found = new Set();
      for (const ch of cleaned.toLowerCase()) {
        if (ch >= "a" && ch <= "z") found.add(ch);
      }
      for (const p of preferred) {
        if (found.has(p)) return p;
      }
      return null;
    },

    normalizeMathText(raw, variable = null) {
      let s = raw
        .replace(/\$+/g, "")
        .replace(/\\left|\\right/g, "")
        .replace(/\\frac\{([^{}]+)\}\{([^{}]+)\}/g, "(($1)/($2))")
        .replace(/\\sqrt\{([^{}]+)\}/g, "sqrt($1)")
        .replace(/\^\{([^{}]+)\}/g, "^($1)")
        .replace(/\\cdot/g, "*")
        .replace(/\\times/g, "*")
        .replace(/\\div/g, "/")
        .replace(/\\pi/g, "pi")
        .replace(/\\(sin|cos|tan|asin|acos|atan|ln|log|exp|abs)/g, "$1")
        .replace(/[{}]/g, (m) => (m === "{" ? "(" : ")"))
        .replace(/×/g, "*")
        .replace(/÷/g, "/")
        .replace(/−/g, "-")
        .replace(/–/g, "-")
        .replace(/—/g, "-")
        .replace(/·/g, "*")
        .replace(/•/g, "*")
        .replace(/π/g, "pi")
        .replace(/√\s*\(/g, "sqrt(")
        .replace(/²/g, "^2")
        .replace(/³/g, "^3")
        .replace(/⁴/g, "^4");

      s = s.replace(/√\s*([0-9]+(?:\.[0-9]+)?|[a-zA-Z])/g, "sqrt($1)");
      if (variable !== "x") {
        s = s.replace(/(?<=[0-9)])\s+[xX]\s+(?=[0-9(])/g, " * ");
      }
      // Thousands separators ("1,000") and mixed numbers ("1 1/2" -> "(1+1/2)")
      s = s.replace(/(?<=[0-9]),(?=[0-9]{3}(?![0-9]))/g, "");
      s = s.replace(/(?<![0-9./])([0-9]+)\s+([0-9]+)\s*\/\s*([0-9]+)(?![0-9.])/g, "($1+$2/$3)");
      return s;
    },

    tokenize(expr, variable = null) {
      const s = this.normalizeMathText(expr, variable);
      const tokens = [];
      let i = 0;

      while (i < s.length) {
        const c = s[i];
        if (/\s/.test(c)) {
          i++;
          continue;
        }
        if (/[0-9.]/.test(c)) {
          let numStr = "";
          let dotCount = 0;
          while (i < s.length && /[0-9.]/.test(s[i])) {
            if (s[i] === ".") {
              dotCount++;
              if (dotCount > 1) return null;
            }
            numStr += s[i];
            i++;
          }
          const val = parseFloat(numStr);
          if (Number.isNaN(val)) return null;
          tokens.push({ type: "number", value: val });
          continue;
        }
        if (/[a-zA-Z]/.test(c)) {
          let word = "";
          while (i < s.length && /[a-zA-Z]/.test(s[i])) {
            word += s[i].toLowerCase();
            i++;
          }
          const funcs = new Set(["sqrt", "cbrt", "sin", "cos", "tan", "asin", "acos", "atan", "ln", "log", "exp", "abs"]);
          if (funcs.has(word)) {
            tokens.push({ type: "func", name: word });
          } else if (word === "pi") {
            tokens.push({ type: "number", value: Math.PI });
          } else if (word === "e" && variable !== "e") {
            tokens.push({ type: "number", value: Math.E });
          } else if (word === "mod") {
            tokens.push({ type: "op", op: "%" });
          } else if (variable && word === variable) {
            tokens.push({ type: "var", name: variable });
          } else if (variable && word.split("").every((ch) => ch === variable)) {
            for (let k = 0; k < word.length; k++) {
              if (k > 0) tokens.push({ type: "op", op: "*" });
              tokens.push({ type: "var", name: variable });
            }
          } else {
            return null;
          }
          continue;
        }
        if ("+-*/^%".includes(c)) {
          tokens.push({ type: "op", op: c });
          i++;
          continue;
        }
        if (c === "!") {
          tokens.push({ type: "postfix", op: "!" });
          i++;
          continue;
        }
        if (c === "(") {
          tokens.push({ type: "lparen" });
          i++;
          continue;
        }
        if (c === ")") {
          tokens.push({ type: "rparen" });
          i++;
          continue;
        }
        return null;
      }

      // Insert implicit multiplication: 2x -> 2*x, 3(x+1) -> 3*(x+1), (x+1)(x-1) -> (x+1)*(x-1)
      const out = [];
      for (let idx = 0; idx < tokens.length; idx++) {
        const tok = tokens[idx];
        if (out.length > 0) {
          const prev = out[out.length - 1];
          const prevCanProduceValue =
            prev.type === "number" ||
            prev.type === "var" ||
            prev.type === "rparen" ||
            prev.type === "postfix";
          const currStartsValue =
            tok.type === "var" ||
            tok.type === "lparen" ||
            tok.type === "func" ||
            (tok.type === "number" && (prev.type === "var" || prev.type === "rparen" || prev.type === "postfix"));
          if (prevCanProduceValue && currStartsValue) {
            out.push({ type: "op", op: "*" });
          }
        }
        out.push(tok);
      }
      return out;
    },

    evaluateTokens(tokens, varValue = 0) {
      if (!tokens || tokens.length === 0) return null;
      let index = 0;

      function parseExpression() {
        let lhs = parseTerm();
        if (lhs === null) return null;
        while (index < tokens.length && tokens[index].type === "op" && (tokens[index].op === "+" || tokens[index].op === "-")) {
          const op = tokens[index].op;
          index++;
          const rhs = parseTerm();
          if (rhs === null) return null;
          lhs = op === "+" ? lhs + rhs : lhs - rhs;
        }
        return lhs;
      }

      function parseTerm() {
        let lhs = parseUnary();
        if (lhs === null) return null;
        while (
          index < tokens.length &&
          tokens[index].type === "op" &&
          (tokens[index].op === "*" || tokens[index].op === "/" || tokens[index].op === "%")
        ) {
          const op = tokens[index].op;
          index++;
          const rhs = parseUnary();
          if (rhs === null) return null;
          if (op === "*") lhs *= rhs;
          else if (op === "/") {
            if (Math.abs(rhs) < 1e-15) return null;
            lhs /= rhs;
          } else {
            if (Math.abs(rhs) < 1e-15) return null;
            lhs = lhs % rhs;
          }
        }
        return lhs;
      }

      function parseUnary() {
        if (index < tokens.length && tokens[index].type === "op") {
          if (tokens[index].op === "+") {
            index++;
            return parseUnary();
          }
          if (tokens[index].op === "-") {
            index++;
            const v = parseUnary();
            return v === null ? null : -v;
          }
        }
        return parsePower();
      }

      function parsePower() {
        let base = parsePostfix();
        if (base === null) return null;
        if (index < tokens.length && tokens[index].type === "op" && tokens[index].op === "^") {
          index++;
          const exp = parseUnary();
          if (exp === null) return null;
          base = Math.pow(base, exp);
        }
        return base;
      }

      function parsePostfix() {
        let val = parsePrimary();
        if (val === null) return null;
        while (index < tokens.length && tokens[index].type === "postfix" && tokens[index].op === "!") {
          index++;
          if (val < 0 || val > 170 || Math.abs(val - Math.round(val)) > 1e-9) return null;
          const n = Math.round(val);
          let acc = 1;
          for (let k = 2; k <= n; k++) acc *= k;
          val = acc;
        }
        return val;
      }

      function parsePrimary() {
        if (index >= tokens.length) return null;
        const tok = tokens[index];
        if (tok.type === "number") {
          index++;
          return tok.value;
        }
        if (tok.type === "var") {
          index++;
          return varValue;
        }
        if (tok.type === "lparen") {
          index++;
          const inside = parseExpression();
          if (inside === null) return null;
          if (index >= tokens.length || tokens[index].type !== "rparen") return null;
          index++;
          return inside;
        }
        if (tok.type === "func") {
          const name = tok.name;
          index++;
          let arg = null;
          if (index < tokens.length && tokens[index].type === "lparen") {
            index++;
            arg = parseExpression();
            if (arg === null || index >= tokens.length || tokens[index].type !== "rparen") return null;
            index++;
          } else {
            arg = parseUnary();
          }
          if (arg === null) return null;
          // Angles such as 30, 45, 90 or anything past 2π are read as degrees.
          const radians = (commonDegrees) =>
            Math.abs(arg) > 2 * Math.PI || commonDegrees.includes(Math.abs(arg)) ? (arg * Math.PI) / 180 : arg;
          switch (name) {
            case "sqrt": return arg >= 0 ? Math.sqrt(arg) : null;
            case "cbrt": return Math.cbrt(arg);
            case "sin": return Math.sin(radians([30, 45, 60, 90, 120, 135, 150, 180, 270, 360]));
            case "cos": return Math.cos(radians([30, 45, 60, 90, 120, 135, 150, 180, 270, 360]));
            case "tan": return Math.tan(radians([30, 45, 60, 120, 135, 150, 180, 360]));
            case "asin": return Math.abs(arg) <= 1 ? Math.asin(arg) : null;
            case "acos": return Math.abs(arg) <= 1 ? Math.acos(arg) : null;
            case "atan": return Math.atan(arg);
            case "ln": return arg > 0 ? Math.log(arg) : null;
            case "log": return arg > 0 ? Math.log10(arg) : null;
            case "exp": return Math.exp(arg);
            case "abs": return Math.abs(arg);
            default: return null;
          }
        }
        return null;
      }

      const res = parseExpression();
      if (res === null || index !== tokens.length || !Number.isFinite(res)) return null;
      return res;
    },

    unitTable: {
      mm: [0.001, "len"], cm: [0.01, "len"], m: [1.0, "len"], km: [1000.0, "len"],
      in: [0.0254, "len"], ft: [0.3048, "len"],
      mg: [0.001, "mass"], g: [1.0, "mass"], kg: [1000.0, "mass"],
      ms: [0.001, "time"], s: [1.0, "time"], sec: [1.0, "time"], min: [60.0, "time"], hr: [3600.0, "time"], h: [3600.0, "time"],
      ml: [0.001, "vol"], l: [1.0, "vol"]
    },

    // "5 m" or "5 m + 30 cm": the value in the first unit, and what it comes to in base units.
    evaluateQuantity(raw) {
      const m = raw.trim().match(/^(-?[0-9]*\.?[0-9]+)\s*([a-zA-Z]+)(?:\s*([+\-−])\s*([0-9]*\.?[0-9]+)\s*([a-zA-Z]+))?$/);
      if (!m) return null;
      const unit = m[2].toLowerCase();
      const first = this.unitTable[unit];
      if (!first) return null;
      let baseValue = parseFloat(m[1]) * first[0];
      if (m[3]) {
        const second = this.unitTable[m[5].toLowerCase()];
        if (!second || second[1] !== first[1]) return null;
        const added = parseFloat(m[4]) * second[0];
        baseValue = m[3] === "+" ? baseValue + added : baseValue - added;
      }
      return { value: baseValue / first[0], unit, factor: first[0], baseValue, dimension: first[1] };
    },

    // A segment of a numeric chain: a quantity with units, or a plain number/expression.
    evaluateSegment(raw) {
      const quantity = this.evaluateQuantity(raw);
      if (quantity) return quantity;
      let value = this.evaluateConstant(raw);
      if (value === null) {
        const tokens = this.tokenize(raw, null);
        value = tokens ? this.evaluateTokens(tokens, 0) : null;
      }
      return value === null ? null : { value, unit: null, factor: 1, baseValue: value, dimension: null };
    },

    // True when `written` is a plain decimal equal to `exact` rounded (or cut off) to the places
    // written, so "22/7 = 3.14" and "sqrt(2) = 1.414" count as right.
    isRounding(written, exact) {
      const m = written.trim().match(/^(-?[0-9]*)[.,]([0-9]+)\s*[a-zA-Z]*$/);
      if (!m) return false;
      const value = parseFloat(`${m[1] || "0"}.${m[2]}`.replace(/^-\./, "-0."));
      if (!Number.isFinite(value)) return false;
      const places = m[2].length;
      const step = Math.pow(10, -places);
      const error = Math.abs(exact - value);
      if (error <= step / 2 + 1e-9) return true;
      // Cut off instead of rounded (2/3 = 0.66): accept from two places on.
      return places >= 2 && error < step && Math.abs(value) < Math.abs(exact) && value < 0 === exact < 0;
    },

    // Reads a line that lists several solutions: "x = 2 or x = 3", "x = 2, 3", "x = ±4".
    solutionList(raw) {
      const parts = raw
        .toLowerCase()
        .trim()
        .split(/\s+(?:or|and)\s+|,\s+|;/)
        .map((p) => p.trim())
        .filter(Boolean);
      let variable = null;
      const roots = [];
      for (const part of parts) {
        let value = part;
        const eq = part.indexOf("=");
        if (eq >= 0) {
          const name = part.slice(0, eq).trim();
          if (!/^[a-z]$/.test(name) || (variable !== null && variable !== name)) return null;
          variable = name;
          value = part.slice(eq + 1).trim();
        } else if (variable === null) {
          return null;
        }
        let bothSigns = false;
        for (const prefix of ["±", "+/-", "+-"]) {
          if (value.startsWith(prefix)) {
            bothSigns = true;
            value = value.slice(prefix.length);
            break;
          }
        }
        if (value.includes("=") || this.detectVariable(value) !== null) return null;
        const tokens = this.tokenize(value, null);
        const number = tokens ? this.evaluateTokens(tokens, 0) : null;
        if (number === null) return null;
        roots.push(number);
        if (bothSigns && Math.abs(number) > 1e-12) roots.push(-number);
      }
      if (variable === null || roots.length < 2) return null;
      return { variable, roots: roots.sort((a, b) => a - b) };
    },

    // "x = 2 or x = 3"
    formatSolutions(roots, variable) {
      return roots.map((r) => `${variable} = ${WorkChecker.formatNumber(r)}`).join(" or ");
    },

    // True when every value in `subset` is one of `roots`.
    rootsAmong(subset, roots) {
      return subset.length > 0 && subset.every((v) => roots.some((r) => Math.abs(r - v) < 1e-4));
    },

    // True for a finished answer: "x = 4", "4 = x", "x = 2 or x = 3".
    isSolvedForm(line) {
      if (this.solutionList(line)) return true;
      const parts = line.split("=").map((p) => p.trim().toLowerCase());
      if (parts.length !== 2) return false;
      return [[parts[0], parts[1]], [parts[1], parts[0]]].some(([name, value]) => {
        if (!/^[a-z]$/.test(name) || this.detectVariable(value) !== null) return false;
        const tokens = this.tokenize(value, null);
        return tokens !== null && this.evaluateTokens(tokens, 0) !== null;
      });
    },

    evaluateSpecialPhrase(raw) {
      const trimmed = raw.trim();
      const pctMatch = trimmed.match(/^([0-9]+(?:\.[0-9]+)?)\s*%\s*of\s*([0-9]+(?:\.[0-9]+)?)$/i);
      if (pctMatch) {
        return (parseFloat(pctMatch[1]) / 100.0) * parseFloat(pctMatch[2]);
      }
      const unitTable = this.unitTable;
      const unitMatch = trimmed.match(/^([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Z]+)\s+(?:in|to)\s+([a-zA-Z]+)$/i);
      if (unitMatch) {
        const val = parseFloat(unitMatch[1]);
        const u1 = unitTable[unitMatch[2].toLowerCase()];
        const u2 = unitTable[unitMatch[3].toLowerCase()];
        if (u1 && u2 && u1[1] === u2[1]) {
          return (val * u1[0]) / u2[0];
        }
      }
      return null;
    },

    evaluateConstant(raw) {
      const special = this.evaluateSpecialPhrase(raw);
      if (special !== null) return special;
      if (this.detectVariable(raw) !== null) return null;
      const tokens = this.tokenize(raw, null);
      if (!tokens) return null;
      const hasOpOrFunc = tokens.some((t) => t.type === "op" || t.type === "func" || t.type === "postfix");
      const isNamedConst = /^\s*(pi|π)\s*$/i.test(raw);
      if (!hasOpOrFunc && !isNamedConst) return null;
      return this.evaluateTokens(tokens, 0);
    },

    polynomialCoefficients(expr, variable) {
      const tokens = this.tokenize(expr, variable);
      if (!tokens) return null;
      const f0 = this.evaluateTokens(tokens, 0);
      const f1 = this.evaluateTokens(tokens, 1);
      const fm1 = this.evaluateTokens(tokens, -1);
      const f2 = this.evaluateTokens(tokens, 2);
      if (f0 === null || f1 === null || fm1 === null || f2 === null) return null;

      const c0 = f0;
      const c2 = 0.5 * (f1 + fm1) - c0;
      const s1 = 0.5 * (f1 - fm1);
      const c3 = (f2 - c0 - 2.0 * s1 - 4.0 * c2) / 6.0;
      const c1 = s1 - c3;

      for (const x of [3.0, -2.5, 0.5]) {
        const actual = this.evaluateTokens(tokens, x);
        if (actual === null) return null;
        const poly = c0 + c1 * x + c2 * x * x + c3 * x * x * x;
        if (Math.abs(actual - poly) > 1e-5) return null;
      }
      return [c0, c1, c2, c3];
    },

    formatPolynomial(coeffs, variable) {
      const terms = [];
      for (let deg = coeffs.length - 1; deg >= 0; deg--) {
        const c = coeffs[deg];
        if (Math.abs(c) < 1e-7) continue;
        const isNeg = c < 0;
        const absC = Math.abs(c);
        let body = "";
        if (deg === 0) {
          body = WorkChecker.formatNumber(absC);
        } else if (deg === 1) {
          body = Math.abs(absC - 1.0) < 1e-7 ? variable : `${WorkChecker.formatNumber(absC)}${variable}`;
        } else {
          const coeffPart = Math.abs(absC - 1.0) < 1e-7 ? "" : WorkChecker.formatNumber(absC);
          body = `${coeffPart}${variable}^${deg}`;
        }
        terms.push({ isNeg, body });
      }
      if (terms.length === 0) return "0";
      let out = (terms[0].isNeg ? "-" : "") + terms[0].body;
      for (let i = 1; i < terms.length; i++) {
        out += (terms[i].isNeg ? " - " : " + ") + terms[i].body;
      }
      return out;
    },

    analyzeEquation(left, right) {
      const combined = `${left} = ${right}`;
      const v = this.detectVariable(combined);
      if (!v) return null;

      const lTokens = this.tokenize(left, v);
      const rTokens = this.tokenize(right, v);
      if (!lTokens || !rTokens) return null;

      const lPoly = this.polynomialCoefficients(left, v);
      const rPoly = this.polynomialCoefficients(right, v);

      if (lPoly && rPoly) {
        const d0 = lPoly[0] - rPoly[0];
        const d1 = lPoly[1] - rPoly[1];
        const d2 = lPoly[2] - rPoly[2];
        const d3 = lPoly[3] - rPoly[3];

        // Identity (e.g. 3(x + 2) = 3x + 6)
        if (Math.abs(d0) < 1e-6 && Math.abs(d1) < 1e-6 && Math.abs(d2) < 1e-6 && Math.abs(d3) < 1e-6) {
          return { variable: v, roots: [], isIdentity: true, isContradiction: false, leftPoly: lPoly, rightPoly: rPoly };
        }
        // Contradiction (e.g. 2x + 1 = 2x + 5)
        if (Math.abs(d1) < 1e-7 && Math.abs(d2) < 1e-7 && Math.abs(d3) < 1e-7 && Math.abs(d0) >= 1e-6) {
          return { variable: v, roots: [], isIdentity: false, isContradiction: true, leftPoly: lPoly, rightPoly: rPoly };
        }
        // Linear: d1 * x + d0 = 0
        if (Math.abs(d2) < 1e-7 && Math.abs(d3) < 1e-7 && Math.abs(d1) >= 1e-7) {
          const root = -d0 / d1;
          return { variable: v, roots: [root], isIdentity: false, isContradiction: false, leftPoly: lPoly, rightPoly: rPoly };
        }
        // Quadratic: d2 * x^2 + d1 * x + d0 = 0
        if (Math.abs(d3) < 1e-7 && Math.abs(d2) >= 1e-7) {
          const disc = d1 * d1 - 4.0 * d2 * d0;
          if (disc < -1e-7) {
            return { variable: v, roots: [], isIdentity: false, isContradiction: true, noRealRoots: true, leftPoly: lPoly, rightPoly: rPoly };
          }
          if (Math.abs(disc) <= 1e-7) {
            return { variable: v, roots: [-d1 / (2.0 * d2)], isIdentity: false, isContradiction: false, leftPoly: lPoly, rightPoly: rPoly };
          }
          const s = Math.sqrt(Math.max(0, disc));
          const r1 = (-d1 - s) / (2.0 * d2);
          const r2 = (-d1 + s) / (2.0 * d2);
          return {
            variable: v,
            roots: [r1, r2].sort((a, b) => a - b),
            isIdentity: false,
            isContradiction: false,
            leftPoly: lPoly,
            rightPoly: rPoly
          };
        }
      }

      // Numerical Newton-Raphson fallback
      const seeds = [-10, -5, -2, -1, -0.5, 0, 0.5, 1, 2, 5, 10];
      const foundRoots = [];
      for (const seed of seeds) {
        let x = seed;
        for (let iter = 0; iter < 28; iter++) {
          const lv = this.evaluateTokens(lTokens, x);
          const rv = this.evaluateTokens(rTokens, x);
          if (lv === null || rv === null) break;
          const fx = lv - rv;
          if (Math.abs(fx) < 1e-7) {
            if (!foundRoots.some((r) => Math.abs(r - x) < 1e-4)) foundRoots.push(x);
            break;
          }
          const h = 1e-5;
          const lvh = this.evaluateTokens(lTokens, x + h);
          const rvh = this.evaluateTokens(rTokens, x + h);
          if (lvh === null || rvh === null) break;
          const df = (lvh - rvh - fx) / h;
          if (Math.abs(df) < 1e-9) break;
          x -= fx / df;
        }
      }
      if (foundRoots.length > 0) {
        return {
          variable: v,
          roots: foundRoots.sort((a, b) => a - b),
          isIdentity: false,
          isContradiction: false,
          leftPoly: lPoly,
          rightPoly: rPoly
        };
      }
      return null;
    }
  };

  // ============================================================================
  // 2. Prose & Composition Style Checker (Port of WritingStyleChecker)
  // ============================================================================
  const WritingStyleChecker = {
    styleRules: [
      { wrong: "could of", right: "could have", note: "Use 'could have' instead of 'could of'." },
      { wrong: "should of", right: "should have", note: "Use 'should have' instead of 'should of'." },
      { wrong: "would of", right: "would have", note: "Use 'would have' instead of 'would of'." },
      { wrong: "must of", right: "must have", note: "Use 'must have' instead of 'must of'." },
      { wrong: "alot", right: "a lot", note: "'a lot' is written as two words." },
      { wrong: "definately", right: "definitely", note: "Spelling: 'definitely'." },
      { wrong: "occured", right: "occurred", note: "Spelling: 'occurred' has two r's." },
      { wrong: "seperate", right: "separate", note: "Spelling: 'separate'." },
      { wrong: "recieve", right: "receive", note: "Spelling: 'receive' (i before e except after c)." },
      { wrong: "untill", right: "until", note: "Spelling: 'until' has one l." },
      { wrong: "wierd", right: "weird", note: "Spelling: 'weird'." },
      { wrong: "accomodate", right: "accommodate", note: "Spelling: 'accommodate' (two c's, two m's)." },
      { wrong: "neccessary", right: "necessary", note: "Spelling: 'necessary' (one c, two s's)." },
      { wrong: "their is", right: "there is", note: "Use 'there is' for existence ('their' is possessive)." },
      { wrong: "their are", right: "there are", note: "Use 'there are' for existence ('their' is possessive)." },
      { wrong: "you're own", right: "your own", note: "Use possessive 'your own' instead of 'you're own'." },
      { wrong: "your welcome", right: "you're welcome", note: "Use contraction 'you're welcome' ('you are')." },
      { wrong: "its a ", right: "it's a ", note: "Use 'it's' (it is) with an apostrophe." },
      { wrong: "more better", right: "better", note: "Avoid double comparatives ('better', not 'more better')." },
      { wrong: "better then", right: "better than", note: "Use 'than' for comparisons ('then' is for time)." },
      { wrong: "more then", right: "more than", note: "Use 'than' for comparisons ('then' is for time)." },
      { wrong: "less then", right: "less than", note: "Use 'than' for comparisons ('then' is for time)." },
      { wrong: "due to the fact that", right: "because", note: "Style guide (conciseness): prefer 'because' over 'due to the fact that'." },
      { wrong: "in order to", right: "to", note: "Style guide (conciseness): prefer 'to' over 'in order to'." },
      { wrong: "at this point in time", right: "now", note: "Style guide (conciseness): prefer 'now' over 'at this point in time'." },
      { wrong: "for the purpose of", right: "to", note: "Style guide (conciseness): prefer 'to' over 'for the purpose of'." },
      { wrong: "in the event that", right: "if", note: "Style guide (conciseness): prefer 'if' over 'in the event that'." }
    ],

    check(raw) {
      const trimmed = raw.trim();
      if (trimmed.length < 4) return null;
      const hasLetters = /[a-zA-Z]{2,}/.test(trimmed);
      if (!hasLetters) return null;

      // 1. Repeated consecutive word check (e.g. "the the")
      const tokens = trimmed.split(/\s+/);
      for (let i = 0; i + 1 < tokens.length; i++) {
        const w1 = tokens[i].replace(/^[^a-zA-Z0-9]+|[^a-zA-Z0-9]+$/g, "").toLowerCase();
        const w2 = tokens[i + 1].replace(/^[^a-zA-Z0-9]+|[^a-zA-Z0-9]+$/g, "").toLowerCase();
        if (w1.length >= 2 && w1 === w2 && /^[a-z]+$/.test(w1)) {
          const fixedTokens = tokens.slice();
          fixedTokens.splice(i + 1, 1);
          return {
            kind: "needsAttention",
            category: "style",
            message: `Style: repeated word '${w1} ${w2}'`,
            expectedValue: w1,
            replacementText: fixedTokens.join(" ")
          };
        }
      }

      // 2. Phrase & grammar/style rules
      for (const rule of this.styleRules) {
        const escaped = rule.wrong.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        const re = new RegExp(`\\b${escaped}\\b`, "i");
        const match = trimmed.match(re);
        if (match) {
          const matchedText = match[0];
          let replacement = rule.right;
          if (matchedText[0] && matchedText[0] === matchedText[0].toUpperCase() && matchedText[0] !== matchedText[0].toLowerCase()) {
            replacement = replacement.charAt(0).toUpperCase() + replacement.slice(1);
          }
          const fixed = trimmed.replace(re, replacement);
          return {
            kind: "needsAttention",
            category: "style",
            message: rule.note,
            expectedValue: replacement.trim(),
            replacementText: fixed
          };
        }
      }

      // 3. Unbalanced double quotes
      const quoteCount = (trimmed.match(/"/g) || []).length;
      if (quoteCount % 2 === 1 && trimmed.length > 8) {
        return {
          kind: "needsAttention",
          category: "style",
          message: 'Style: unclosed quotation mark (")',
          expectedValue: `${trimmed}"`,
          replacementText: `${trimmed}"`
        };
      }

      return null;
    }
  };

  // ============================================================================
  // 3. Multi-Step WorkChecker Engine (Port of WorkChecker.swift)
  // ============================================================================
  const WorkChecker = {
    formatNumber(val) {
      if (!Number.isFinite(val)) return "";
      if (Math.abs(val) < 1e-10) return "0";
      if (Math.abs(val - Math.round(val)) < 1e-9) {
        return String(Math.round(val));
      }
      for (const denom of [2, 3, 4, 5, 6, 8, 10, 12]) {
        const num = val * denom;
        if (Math.abs(num - Math.round(num)) < 1e-6) {
          const roundedFixed = Number(val.toFixed(4));
          if (Math.abs(val - roundedFixed) < 1e-8) {
            return String(roundedFixed);
          }
          return `${Math.round(num)}/${denom}`;
        }
      }
      return String(Number(val.toFixed(4)));
    },

    // A decimal answer for arithmetic ("0.6667"), where a fraction would just repeat the question.
    formatDecimal(val) {
      if (!Number.isFinite(val)) return "";
      if (Math.abs(val - Math.round(val)) < 1e-9) return String(Math.round(val));
      return String(Number(val.toFixed(4)));
    },

    rootsMatch(r1, r2) {
      if (r1.length !== r2.length) return false;
      for (let i = 0; i < r1.length; i++) {
        if (Math.abs(r1[i] - r2[i]) > 1e-4) return false;
      }
      return true;
    },

    // "5 m + 30 cm" -> "5.3 m" (a lone quantity such as "5 m" has nothing to work out)
    evaluateUnitSum(raw) {
      const quantity = AlgebraicEngine.evaluateQuantity(raw);
      if (!quantity || !/[+\-−]/.test(raw.trim().slice(1))) return null;
      return `${this.formatDecimal(quantity.value)} ${quantity.unit}`;
    },

    diagnoseAlgebraSlip(previous, current, prevText, currText) {
      const v = current.variable;
      const expectedAssignment = AlgebraicEngine.formatSolutions(previous.roots, v);
      if (previous.roots.length > 1) {
        return {
          kind: "needsAttention",
          category: "algebra",
          message: `Step changes the solutions: '${prevText}' gives ${expectedAssignment}`,
          expectedValue: expectedAssignment,
          replacementText: expectedAssignment
        };
      }

      if (previous.leftPoly && previous.rightPoly && current.leftPoly && current.rightPoly) {
        const pL0 = previous.leftPoly[0], pL1 = previous.leftPoly[1];
        const pR0 = previous.rightPoly[0], pR1 = previous.rightPoly[1];
        const cL0 = current.leftPoly[0], cL1 = current.leftPoly[1];
        const cR0 = current.rightPoly[0], cR1 = current.rightPoly[1];

        // Case A: Sign slip moving constant from LHS to RHS (e.g. 2x + 6 = 14 -> 2x = 20)
        if (Math.abs(pL0) > 1e-6 && Math.abs(cL0) < 1e-6 && Math.abs(pL1 - cL1) < 1e-6 && Math.abs(pR1 - cR1) < 1e-6) {
          const correctRHS = pR0 - pL0;
          const wrongSignRHS = pR0 + pL0;
          if (Math.abs(cR0 - wrongSignRHS) < 1e-5) {
            const lhsStr = AlgebraicEngine.formatPolynomial([0, cL1, current.leftPoly[2], current.leftPoly[3]], v);
            const fixedLine = `${lhsStr} = ${this.formatNumber(correctRHS)}`;
            const opWord = pL0 > 0 ? `subtract ${this.formatNumber(pL0)} from` : `add ${this.formatNumber(Math.abs(pL0))} to`;
            return {
              kind: "needsAttention",
              category: "algebra",
              message: `Sign slip: ${opWord} both sides → ${fixedLine}, not ${this.formatNumber(cR0)}`,
              expectedValue: fixedLine,
              replacementText: fixedLine
            };
          }
        }

        // Case B: Distribution slip (e.g. 3(x - 2) = 9 -> 3x - 2 = 9)
        if (prevText.includes("(") && !currText.includes("(") && Math.abs(pL1 - cL1) < 1e-6 && Math.abs(pL0 - cL0) > 1e-5) {
          const correctLHS = AlgebraicEngine.formatPolynomial(previous.leftPoly, v);
          const rhsStr = AlgebraicEngine.formatPolynomial(previous.rightPoly, v);
          const fixedLine = `${correctLHS} = ${rhsStr}`;
          return {
            kind: "needsAttention",
            category: "algebra",
            message: `Distribution slip: left side expands to ${correctLHS} (multiply every term inside parentheses)`,
            expectedValue: fixedLine,
            replacementText: fixedLine
          };
        }

        // Case C: Final isolation step x = k
        const currParts = currText.split("=");
        if (currParts.length === 2 && currParts[0].trim().toLowerCase() === v) {
          return {
            kind: "needsAttention",
            category: "algebra",
            message: `Check division/isolation: from '${prevText}', ${expectedAssignment}`,
            expectedValue: expectedAssignment,
            replacementText: expectedAssignment
          };
        }

        // General linear step correction
        if (Math.abs(cL1) > 1e-6 && Math.abs(cR1) < 1e-6 && Math.abs(cL0) < 1e-6) {
          const correctRHS = cL1 * previous.roots[0];
          const lhsStr = AlgebraicEngine.formatPolynomial([0, cL1, 0, 0], v);
          const fixedLine = `${lhsStr} = ${this.formatNumber(correctRHS)}`;
          return {
            kind: "needsAttention",
            category: "algebra",
            message: `Step doesn't follow from '${prevText}' — expected ${fixedLine} (so ${expectedAssignment})`,
            expectedValue: fixedLine,
            replacementText: fixedLine
          };
        }
      }

      return {
        kind: "needsAttention",
        category: "algebra",
        message: `Algebraic step changes solution: '${prevText}' has ${expectedAssignment}`,
        expectedValue: expectedAssignment,
        replacementText: expectedAssignment
      };
    },

    evaluateLine(rawText, previousStep = null) {
      let cleaned = rawText.trim();
      cleaned = cleaned.replace(/^(\([0-9a-zA-Z]+\)|[0-9]+\.|[•\-*])\s+/, "");
      if (!cleaned) {
        return { kind: "tracking", category: "general", message: "Following your writing…", expectedValue: null, replacementText: null };
      }

      // 1. Equations & chained equalities (contains '=')
      if (cleaned.includes("=") && !cleaned.includes("==") && !cleaned.includes("!=") && !cleaned.includes("<=") && !cleaned.includes(">=")) {
        const rawSegments = cleaned.split("=").map((s) => s.trim());
        const nonEmpty = rawSegments.filter((s) => s.length > 0);
        const endsWithEquals = cleaned.endsWith("=") && rawSegments[rawSegments.length - 1] === "";

        // 1a. Trailing '=' (e.g. "24 * 15 =" or "2(x + 3) =")
        if (endsWithEquals && nonEmpty.length >= 1) {
          const firstSeg = nonEmpty[0];
          const unitSum = this.evaluateUnitSum(firstSeg);
          if (unitSum) {
            return { kind: "evaluated", category: "arithmetic", message: `${firstSeg} = ${unitSum}`, expectedValue: unitSum, replacementText: `${cleaned} ${unitSum}` };
          }
          const constVal = AlgebraicEngine.evaluateConstant(firstSeg);
          if (constVal !== null) {
            const formatted = this.formatNumber(constVal);
            return {
              kind: "evaluated",
              category: "arithmetic",
              message: `${firstSeg} = ${formatted}`,
              expectedValue: formatted,
              replacementText: `${cleaned} ${formatted}`
            };
          }
          const v = AlgebraicEngine.detectVariable(firstSeg);
          if (v) {
            const coeffs = AlgebraicEngine.polynomialCoefficients(firstSeg, v);
            if (coeffs) {
              const simplified = AlgebraicEngine.formatPolynomial(coeffs, v);
              if (simplified.replace(/\s+/g, "") !== firstSeg.replace(/\s+/g, "").toLowerCase()) {
                return {
                  kind: "evaluated",
                  category: "algebra",
                  message: `Simplifies to ${simplified}`,
                  expectedValue: simplified,
                  replacementText: `${cleaned} ${simplified}`
                };
              }
            }
          }
        }

        // 1b. A list of solutions ("x = 2 or x = 3", "x = ±4") checked against the equation above
        const listed = AlgebraicEngine.solutionList(cleaned);
        if (listed) {
          if (previousStep && previousStep.variable === listed.variable && previousStep.roots.length > 0) {
            const expected = AlgebraicEngine.formatSolutions(previousStep.roots, previousStep.variable);
            if (this.rootsMatch(previousStep.roots, listed.roots)) {
              return { kind: "verified", category: "algebra", message: `Solutions verified: ${expected}`, expectedValue: expected, replacementText: null };
            }
            return {
              kind: "needsAttention",
              category: "algebra",
              message: `Check the solutions: '${previousStep.rawText}' gives ${expected}`,
              expectedValue: expected,
              replacementText: expected
            };
          }
          return { kind: "tracking", category: "general", message: `Following: "${cleaned}"`, expectedValue: null, replacementText: null };
        }

        // 1c. Two or more segments around '='
        if (nonEmpty.length >= 2) {
          const quantities = nonEmpty.map((seg) => AlgebraicEngine.evaluateSegment(seg));
          if (quantities.every((q) => q !== null)) {
            // Numbers or units all the way along (e.g. "12 + 8 = 4 * 5 = 20", "5 m + 30 cm = 5.3 m")
            const first = quantities[0];
            const fixedSegments = nonEmpty.slice();
            let firstSlip = null;
            let rounded = false;
            let unjudged = false;

            for (let idx = 1; idx < quantities.length; idx++) {
              const current = quantities[idx];
              if (first.unit && current.unit && first.dimension !== current.dimension) {
                return {
                  kind: "needsAttention",
                  category: "arithmetic",
                  message: `Unit mismatch: ${first.unit} vs ${current.unit}`,
                  expectedValue: null,
                  replacementText: null
                };
              }
              // Compare in base units when both sides carry a unit; a bare number is read in
              // the first segment's unit ("50 cm + 50 cm = 100").
              const bothUnits = Boolean(first.unit && current.unit);
              const lhs = bothUnits ? first.baseValue : first.value;
              const rhs = bothUnits ? current.baseValue : current.value;
              if (Math.abs(lhs - rhs) <= Math.max(1e-6, Math.abs(lhs) * 1e-6)) continue;

              // The right answer in the unit this segment was written in ("2 km = 2000 m").
              const expectedHere = bothUnits ? first.baseValue / current.factor : first.value;
              if (AlgebraicEngine.isRounding(nonEmpty[idx], expectedHere)) {
                rounded = true;
                continue;
              }
              // One quantity against a bare number can't be judged: "5m = 500" may be algebra.
              if (Boolean(first.unit) !== Boolean(current.unit)) {
                const withUnit = first.unit ? nonEmpty[0] : nonEmpty[idx];
                if (!/[+\-−]/.test(withUnit.slice(1))) {
                  unjudged = true;
                  break;
                }
              }
              const expectedText = this.formatDecimal(expectedHere) + (bothUnits ? ` ${current.unit}` : "");
              fixedSegments[idx] = expectedText;
              if (!firstSlip) firstSlip = { expectedText, written: nonEmpty[idx] };
            }

            if (!unjudged) {
              if (firstSlip) {
                return {
                  kind: "needsAttention",
                  category: "arithmetic",
                  message: `Check arithmetic: ${nonEmpty[0]} = ${firstSlip.expectedText} (wrote ${firstSlip.written})`,
                  expectedValue: firstSlip.expectedText,
                  replacementText: fixedSegments.join(" = ")
                };
              }
              return {
                kind: "verified",
                category: "arithmetic",
                message: rounded
                  ? `Verified (rounded): ${nonEmpty[0]} ≈ ${nonEmpty[nonEmpty.length - 1]}`
                  : `Verified: ${nonEmpty.join(" = ")}`,
                expectedValue: this.formatDecimal(first.value) + (first.unit ? ` ${first.unit}` : ""),
                replacementText: null
              };
            }
          } else if (nonEmpty.some((seg) => AlgebraicEngine.detectVariable(seg) !== null)) {
            // Algebraic equation or identity (e.g. "2x + 6 = 14" or "(x + 2)(x + 3) = x^2 + 5x + 6")
            const lhs = nonEmpty[0];
            const rhs = nonEmpty[nonEmpty.length - 1];
            const eqInfo = AlgebraicEngine.analyzeEquation(lhs, rhs);

            if (eqInfo) {
              if (eqInfo.isIdentity) {
                return {
                  kind: "verified",
                  category: "algebra",
                  message: `Verified algebraic identity: ${lhs} = ${rhs}`,
                  expectedValue: rhs,
                  replacementText: null
                };
              }
              if (eqInfo.isContradiction) {
                // A quadratic that never reaches zero (x^2 + 1 = 0) is a fair equation, not a slip.
                if (eqInfo.noRealRoots) {
                  return {
                    kind: "verified",
                    category: "algebra",
                    message: `Equation tracked (no real solutions)`,
                    expectedValue: "no real solutions",
                    replacementText: null
                  };
                }
                // An expansion written out wrongly: 2(x + 3) = 2x + 9, or the same the other way round.
                for (const [bracketed, poly, other] of [[lhs, eqInfo.leftPoly, rhs], [rhs, eqInfo.rightPoly, lhs]]) {
                  if (!bracketed.includes("(") || !poly) continue;
                  const expanded = AlgebraicEngine.formatPolynomial(poly, eqInfo.variable);
                  return {
                    kind: "needsAttention",
                    category: "algebra",
                    message: `Expansion slip: ${bracketed} simplifies to ${expanded}, not ${other}`,
                    expectedValue: expanded,
                    replacementText: bracketed === lhs ? `${lhs} = ${expanded}` : `${expanded} = ${rhs}`
                  };
                }
                return {
                  kind: "needsAttention",
                  category: "algebra",
                  message: `No solution: the two sides differ by a constant (${lhs} = ${rhs})`,
                  expectedValue: null,
                  replacementText: null
                };
              }

              // Compare with previous derivation step on the page if same variable
              if (previousStep && previousStep.variable === eqInfo.variable && previousStep.roots.length > 0 && eqInfo.roots.length > 0) {
                if (this.rootsMatch(previousStep.roots, eqInfo.roots)) {
                  const rootDesc = eqInfo.roots.map((r) => `${eqInfo.variable} = ${this.formatNumber(r)}`).join(", ");
                  return {
                    kind: "verified",
                    category: "algebra",
                    message: `Step verified (${rootDesc})`,
                    expectedValue: rootDesc,
                    replacementText: null
                  };
                }
                if (eqInfo.roots.length < previousStep.roots.length && AlgebraicEngine.rootsAmong(eqInfo.roots, previousStep.roots)) {
                  // One of several solutions (x^2 = 16, then x = 4): right, but not the whole answer.
                  const found = AlgebraicEngine.formatSolutions(eqInfo.roots, eqInfo.variable);
                  const others = AlgebraicEngine.formatSolutions(
                    previousStep.roots.filter((r) => !AlgebraicEngine.rootsAmong([r], eqInfo.roots)),
                    eqInfo.variable
                  );
                  return {
                    kind: "verified",
                    category: "algebra",
                    message: `Verified: ${found} is a solution (also ${others})`,
                    expectedValue: found,
                    replacementText: null,
                    partialSolution: true
                  };
                }
                return this.diagnoseAlgebraSlip(previousStep, eqInfo, previousStep.rawText, cleaned);
              }

              // Standalone equation line
              if (eqInfo.roots.length > 0) {
                const rootDesc = eqInfo.roots.map((r) => `${eqInfo.variable} = ${this.formatNumber(r)}`).join(", ");
                const isSolvedForm =
                  lhs.trim().toLowerCase() === eqInfo.variable ||
                  rhs.trim().toLowerCase() === eqInfo.variable;
                return {
                  kind: "verified",
                  category: "algebra",
                  message: isSolvedForm ? `Verified solution: ${rootDesc}` : `Equation tracked (${rootDesc})`,
                  expectedValue: rootDesc,
                  replacementText: null
                };
              }
            }
          }
        }
      }

      // 2. Standalone arithmetic, unit conversion, or percentage expression without '='
      const standaloneUnitSum = cleaned.includes("=") ? null : this.evaluateUnitSum(cleaned);
      if (standaloneUnitSum) {
        return {
          kind: "evaluated",
          category: "arithmetic",
          message: `${cleaned} = ${standaloneUnitSum}`,
          expectedValue: standaloneUnitSum,
          replacementText: `${cleaned} = ${standaloneUnitSum}`
        };
      }
      const standaloneVal = AlgebraicEngine.evaluateConstant(cleaned);
      if (standaloneVal !== null) {
        const formatted = this.formatNumber(standaloneVal);
        return {
          kind: "evaluated",
          category: "arithmetic",
          message: `${cleaned} = ${formatted}`,
          expectedValue: formatted,
          replacementText: `${cleaned} = ${formatted}`
        };
      }

      // 3. Standalone algebraic polynomial simplification (e.g. "3(x + 4) - x")
      const v = AlgebraicEngine.detectVariable(cleaned);
      if (v && /[+\-*/^()]/.test(cleaned)) {
        const coeffs = AlgebraicEngine.polynomialCoefficients(cleaned, v);
        if (coeffs) {
          const simplified = AlgebraicEngine.formatPolynomial(coeffs, v);
          if (simplified.replace(/\s+/g, "") !== cleaned.replace(/\s+/g, "").toLowerCase()) {
            return {
              kind: "evaluated",
              category: "algebra",
              message: `Simplifies to ${simplified}`,
              expectedValue: simplified,
              replacementText: `${cleaned} = ${simplified}`
            };
          }
        }
      }

      // 4. Prose & Writing Style Guide Check
      const styleFeedback = WritingStyleChecker.check(cleaned);
      if (styleFeedback) return styleFeedback;

      return {
        kind: "tracking",
        category: "general",
        message: `Following: "${cleaned}"`,
        expectedValue: null,
        replacementText: null
      };
    },

    // Full-page top-to-bottom check with multi-step derivation state
    checkLines(lines, activeIndex) {
      let previousAlgebraStep = null;
      const annotations = [];

      for (let idx = 0; idx < lines.length; idx++) {
        const raw = lines[idx];
        const feedback = this.evaluateLine(raw, previousAlgebraStep);

        // Carry the derivation's context to the next line. A flagged step, or one that gives only
        // some of the solutions, keeps the equation above as context so one slip doesn't cascade.
        // A finished answer ("x = 4") or a line without "=" ends the derivation.
        const eqParts = raw.split("=");
        if (!raw.includes("=")) {
          previousAlgebraStep = null;
        } else if (AlgebraicEngine.isSolvedForm(raw)) {
          const keepsContext = feedback.kind === "needsAttention" || feedback.partialSolution;
          if (!keepsContext) previousAlgebraStep = null;
        } else if (eqParts.length === 2) {
          const eqInfo = AlgebraicEngine.analyzeEquation(eqParts[0].trim(), eqParts[1].trim());
          if (eqInfo && !eqInfo.isContradiction && eqInfo.roots.length > 0) {
            if (feedback.kind !== "needsAttention" || !previousAlgebraStep || previousAlgebraStep.variable !== eqInfo.variable) {
              previousAlgebraStep = {
                variable: eqInfo.variable,
                roots: eqInfo.roots,
                leftPoly: eqInfo.leftPoly,
                rightPoly: eqInfo.rightPoly,
                rawText: raw.trim()
              };
            }
          }
        }

        annotations.push({
          index: idx,
          text: raw,
          feedback,
          isActive: idx === activeIndex
        });
      }
      return annotations;
    },

    // Active Recall & Flashcard Work Comparison (Port of WorkChecker.compareRecall)
    compareRecall(originalText, attemptText) {
      const stopWords = new Set([
        "the", "and", "for", "that", "this", "with", "from", "have", "has", "had",
        "are", "was", "were", "been", "into", "unto", "your", "their", "there",
        "what", "when", "where", "which", "while", "about", "after", "before",
        "between", "under", "over", "some", "such", "than", "then", "them", "they",
        "will", "would", "could", "should", "each", "other", "more", "most", "very"
      ]);

      function extractKeywords(text) {
        const words = text
          .toLowerCase()
          .split(/[^a-z0-9]+/)
          .filter((w) => w.length >= 3 && !stopWords.has(w));
        const seen = new Set();
        const unique = [];
        for (const w of words) {
          if (!seen.has(w)) {
            seen.add(w);
            unique.push(w);
          }
        }
        return unique;
      }

      const origTerms = extractKeywords(originalText);
      const attemptSet = new Set(extractKeywords(attemptText));
      const matched = origTerms.filter((t) => attemptSet.has(t));
      const missed = origTerms.filter((t) => !attemptSet.has(t));

      const verifiedMath = [];
      const mathSlips = [];
      const clauses = attemptText
        .split(/[\n.;,]+/)
        .map((s) => s.trim())
        .filter(Boolean);

      for (const clause of clauses) {
        const fb = this.evaluateLine(clause, null);
        if (fb.category === "style") continue;
        if (fb.kind === "verified") verifiedMath.push(fb.message);
        else if (fb.kind === "needsAttention") mathSlips.push(fb.message);
      }

      // A short answer ("42", "x = 5") has no key terms: the answer itself must be there.
      const compact = (text) => text.toLowerCase().replace(/\s+/g, "");
      let baseScore =
        origTerms.length === 0
          ? (compact(originalText) && compact(attemptText).includes(compact(originalText)) ? 1.0 : 0.0)
          : matched.length / origTerms.length;
      if (mathSlips.length > 0) {
        baseScore = Math.max(0, baseScore - 0.15 * mathSlips.length);
      }
      const accuracy = Math.min(1.0, Math.max(0.0, baseScore));

      let rating = 1;
      if (accuracy >= 0.88 && mathSlips.length === 0) rating = 5;
      else if (accuracy >= 0.7) rating = 4;
      else if (accuracy >= 0.5) rating = 3;
      else if (accuracy >= 0.25) rating = 2;

      return {
        accuracyPercent: Math.round(accuracy * 100),
        matchedTerms: matched.slice(0, 10),
        missedTerms: missed.slice(0, 8),
        verifiedEquations: verifiedMath,
        mathSlips,
        suggestedRating: rating
      };
    }
  };

  // Expose WorkChecker for Node verification tests or console inspection
  if (typeof module !== "undefined" && module.exports) {
    module.exports = { WorkChecker, AlgebraicEngine, WritingStyleChecker };
  }
  if (typeof window !== "undefined") {
    window.ParchmentWorkChecker = WorkChecker;
  }

  // Stop here if running headless in Node test mode without a DOM
  if (typeof document === "undefined") return;

  // ============================================================================
  // 4. Interactive Browser App State & Pre-Loaded Notebooks
  // ============================================================================
  const state = {
    notebooks: [
      {
        id: "nb-algebra",
        title: "Algebra & Step Checker",
        subtitle: "Multi-step derivation & slips",
        folderPath: "Mathematics/Algebra",
        coverColor: "#0A60FF",
        paperStyle: "ruled",
        lines: [
          "Solve linear equation step-by-step:",
          "2x + 6 = 14",
          "2x = 20",
          "x = 4",
          "",
          "Distribution & quadratic check:",
          "3(x - 2) = 9",
          "3x - 2 = 9",
          "(x + 2)(x + 3) = x^2 + 5x + 6"
        ],
        strokes: [],
        attachments: []
      },
      {
        id: "nb-physics",
        title: "Physics, Units & Calc",
        subtitle: "Chained math, units & trig",
        folderPath: "Ship's Log/Navigation",
        coverColor: "#8B4A2E",
        paperStyle: "grid",
        lines: [
          "Chained equalities & arithmetic:",
          "12 + 8 = 4 * 5 = 20",
          "15 * 4 = 62",
          "sqrt(144) + 3^2 =",
          "",
          "Unit conversions & percentages:",
          "2.5 km in m",
          "15% of 80",
          "5! + cos(0) ="
        ],
        strokes: [],
        attachments: []
      },
      {
        id: "nb-writing",
        title: "Composition & Style Guide",
        subtitle: "Grammar & Strunk & White rules",
        folderPath: "Ship's Log/Journal",
        coverColor: "#2E9452",
        paperStyle: "dottedLined",
        lines: [
          "Field Notes — Style Guide Check",
          "We could of finished the the prototype earlier.",
          "Due to the fact that the sensor drifted, recalibrate now.",
          "This design is much better then the previous revision.",
          "Clean, concise sentences pass without distraction."
        ],
        strokes: [],
        attachments: []
      },
      {
        id: "nb-biology",
        title: "Biology — Cellular Respiration",
        subtitle: "Ready for Active Recall check",
        folderPath: "Science/Biology",
        coverColor: "#6B4EFF",
        paperStyle: "dotted",
        lines: [
          "Mitochondria generate ATP through cellular respiration.",
          "Glycolysis splits glucose into two pyruvate molecules.",
          "The Krebs cycle produces NADH and FADH2 in the matrix.",
          "6 * 6 = 36",
          "Total yield is approximately 36 ATP per glucose molecule."
        ],
        strokes: [],
        attachments: []
      }
    ],
    activeNotebookId: "nb-algebra",
    activeFolder: "", // "" = All Logs
    customFolders: ["Ship's Log/Voyages"],
    activeLineIndex: 2,
    followerEnabled: true,
    activeTool: "type", // "type" | "pen" | "highlighter" | "eraser"
    inkColor: "#1F2430",
    inspectorOpen: false,
    newModalCoverColor: "#0A60FF",
    newModalPaperStyle: "ruled",
    syncServerUrl: (typeof localStorage !== "undefined" && localStorage.getItem("bellobook.syncUrl")) || "",
    audioQueue: [],
    audioIndex: -1,
    audioPlaying: false,
    textbookMode: false,
    ankiFlipped: false,
    ankiIndex: 0,
    ankiCards: [
      {
        id: "card-1",
        front: "Mitochondria generate {{c1::ATP::cellular energy}} via oxidative phosphorylation.",
        back: "ATP (adenosine triphosphate)",
        ease: 2.5,
        interval: 0,
        reps: 0,
        due: 0
      },
      {
        id: "card-2",
        front: "Quadratic Formula: $$x = \\frac{-b \\pm \\sqrt{b^{2} - 4ac}}{2a}$$",
        back: "Solves $ax^{2} + bx + c = 0$ for $a \\neq 0$.",
        ease: 2.5,
        interval: 0,
        reps: 0,
        due: 0
      },
      {
        id: "card-3",
        front: "What is the Obsidian syntax for a theorem callout?",
        back: "> [!theorem] Title followed by > body lines",
        ease: 2.5,
        interval: 0,
        reps: 0,
        due: 0
      }
    ]
  };

  function getActiveNotebook() {
    return state.notebooks.find((n) => n.id === state.activeNotebookId) || state.notebooks[0];
  }

  // ----------------------------------------------------------------------------
  // Library storage: everything is kept in this browser (localStorage) so a reload
  // doesn't lose work. The same JSON is what "Download .bellobook.json" exports.
  // ----------------------------------------------------------------------------
  const STORAGE_KEY = "bellobook.library.v1";
  const PAPER_STYLES = ["ruled", "dottedLined", "grid", "dotted", "blank"];
  const ATTACHMENT_KINDS = ["image", "audio", "video", "file"];
  let saveTimer = null;

  function isHexColor(value) {
    return typeof value === "string" && /^#[0-9a-fA-F]{3,8}$/.test(value);
  }

  // Imported and stored data ends up in innerHTML and style attributes, so every field is
  // checked and coerced before it is used.
  function sanitizeAttachment(att) {
    if (!att || typeof att !== "object") return null;
    const dataUrl = typeof att.dataUrl === "string" && /^data:[a-z0-9.+/-]+[;,]/i.test(att.dataUrl) ? att.dataUrl : null;
    return {
      id: String(att.id || "att-" + Date.now() + "-" + Math.random().toString(36).slice(2, 6)),
      kind: ATTACHMENT_KINDS.includes(att.kind) ? att.kind : "file",
      filename: String(att.filename || "attachment"),
      title: String(att.title || att.filename || "Attachment"),
      artist: String(att.artist || ""),
      album: String(att.album || ""),
      mimeType: String(att.mimeType || "application/octet-stream"),
      dataUrl,
      textPreview: typeof att.textPreview === "string" ? att.textPreview : null,
      isDemoSynth: att.isDemoSynth === true
    };
  }

  function sanitizeStroke(stroke) {
    if (!stroke || !Array.isArray(stroke.points)) return null;
    const points = stroke.points
      .filter((p) => p && Number.isFinite(p.x) && Number.isFinite(p.y))
      .map((p) => ({ x: p.x, y: p.y, t: Number.isFinite(p.t) ? p.t : 0 }));
    if (points.length < 2) return null;
    return {
      tool: stroke.tool === "highlighter" ? "highlighter" : "pen",
      color: isHexColor(stroke.color) ? stroke.color : "#1F2430",
      width: Number.isFinite(stroke.width) ? Math.min(40, Math.max(0.5, stroke.width)) : 2.8,
      alpha: Number.isFinite(stroke.alpha) ? Math.min(1, Math.max(0.05, stroke.alpha)) : 1,
      points
    };
  }

  function sanitizeNotebook(nb) {
    if (!nb || typeof nb !== "object") return null;
    return {
      id: String(nb.id || "nb-" + Date.now() + "-" + Math.random().toString(36).slice(2, 6)),
      title: String(nb.title || "Untitled Log"),
      subtitle: String(nb.subtitle || ""),
      folderPath: String(nb.folderPath || ""),
      coverColor: isHexColor(nb.coverColor) ? nb.coverColor : "#0A60FF",
      paperStyle: PAPER_STYLES.includes(nb.paperStyle) ? nb.paperStyle : "ruled",
      lines: Array.isArray(nb.lines) ? nb.lines.map((l) => String(l == null ? "" : l)) : [""],
      strokes: Array.isArray(nb.strokes) ? nb.strokes.map(sanitizeStroke).filter(Boolean) : [],
      attachments: Array.isArray(nb.attachments) ? nb.attachments.map(sanitizeAttachment).filter(Boolean) : []
    };
  }

  function sanitizeCard(card) {
    if (!card || typeof card !== "object" || !card.front) return null;
    const number = (value, fallback) => (Number.isFinite(value) ? value : fallback);
    return {
      id: String(card.id || "card-" + Date.now() + "-" + Math.random().toString(36).slice(2, 6)),
      front: String(card.front),
      back: String(card.back || ""),
      ease: Math.max(1.3, number(card.ease, 2.5)),
      interval: Math.max(0, number(card.interval, 0)),
      reps: Math.max(0, number(card.reps, 0)),
      due: Math.max(0, number(card.due, 0))
    };
  }

  function libraryJSON(includeMedia, pretty) {
    const notebooks = includeMedia
      ? state.notebooks
      : state.notebooks.map((nb) => ({ ...nb, attachments: (nb.attachments || []).map((a) => ({ ...a, dataUrl: null })) }));
    const payload = {
      app: "BelloBook",
      version: 1,
      notebooks,
      customFolders: state.customFolders,
      ankiCards: state.ankiCards,
      activeNotebookId: state.activeNotebookId
    };
    return JSON.stringify(payload, null, pretty ? 2 : 0);
  }

  // Takes a parsed .bellobook.json. With `merge`, notebooks and cards with the same id are
  // replaced and the rest are kept; without it the library is replaced. Returns how many
  // notebooks were read, or 0 if the data isn't a BelloBook library.
  function applyLibrary(data, merge) {
    if (!data || typeof data !== "object" || !Array.isArray(data.notebooks)) return 0;
    const notebooks = data.notebooks.map(sanitizeNotebook).filter(Boolean);
    if (notebooks.length === 0) return 0;
    const cards = Array.isArray(data.ankiCards) ? data.ankiCards.map(sanitizeCard).filter(Boolean) : null;
    const folders = Array.isArray(data.customFolders) ? data.customFolders.map(String).filter(Boolean) : [];

    if (merge) {
      const incoming = new Set(notebooks.map((n) => n.id));
      state.notebooks = [...notebooks, ...state.notebooks.filter((n) => !incoming.has(n.id))];
      if (cards) {
        const incomingCards = new Set(cards.map((c) => c.id));
        state.ankiCards = [...cards, ...state.ankiCards.filter((c) => !incomingCards.has(c.id))];
      }
      state.customFolders = Array.from(new Set([...state.customFolders, ...folders]));
    } else {
      state.notebooks = notebooks;
      if (cards) state.ankiCards = cards;
      state.customFolders = folders;
    }
    const wanted = typeof data.activeNotebookId === "string" ? data.activeNotebookId : null;
    if (!merge && wanted && state.notebooks.some((n) => n.id === wanted)) state.activeNotebookId = wanted;
    if (!state.notebooks.some((n) => n.id === state.activeNotebookId)) state.activeNotebookId = state.notebooks[0].id;
    state.activeLineIndex = 0;
    return notebooks.length;
  }

  function loadSavedLibrary() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (raw) applyLibrary(JSON.parse(raw), false);
    } catch (_) {
      // Unreadable or blocked storage: carry on with the sample notebooks.
    }
  }

  function saveLibrary() {
    clearTimeout(saveTimer);
    saveTimer = null;
    try {
      localStorage.setItem(STORAGE_KEY, libraryJSON(true, false));
      state.mediaNotSaved = false;
    } catch (_) {
      // Usually the storage quota: attachments are the bulky part, so keep everything else.
      try {
        localStorage.setItem(STORAGE_KEY, libraryJSON(false, false));
        state.mediaNotSaved = state.notebooks.some((nb) => (nb.attachments || []).some((a) => a.dataUrl));
      } catch (_) {
        // Storage unavailable (private mode, disabled): nothing more to do.
      }
    }
  }

  function scheduleSave() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(saveLibrary, 400);
  }

  // ============================================================================
  // 5. DOM Rendering & Live Work Follower UI
  // ============================================================================
  const els = {};

  function initDOM() {
    els.folderTree = document.getElementById("folderTree");
    els.notebookList = document.getElementById("notebookList");
    els.paperStyleChips = document.getElementById("paperStyleChips");
    els.activeNotebookCrumb = document.getElementById("activeNotebookCrumb");
    els.paperSheet = document.getElementById("paperSheet");
    els.pageTitleInput = document.getElementById("pageTitleInput");
    els.pageStatusSummary = document.getElementById("pageStatusSummary");
    els.pageAttachmentsStrip = document.getElementById("pageAttachmentsStrip");
    els.workLinesContainer = document.getElementById("workLinesContainer");
    els.inkCanvas = document.getElementById("inkCanvas");
    els.penFollowerDot = document.getElementById("penFollowerDot");
    els.floatingFollowerDock = document.getElementById("floatingFollowerDock");
    els.followerPill = document.getElementById("followerPill");
    els.stepInspectorPopover = document.getElementById("stepInspectorPopover");
    els.stepLogList = document.getElementById("stepLogList");
    els.toggleFollowerBtn = document.getElementById("toggleFollowerBtn");
    els.newNotebookModal = document.getElementById("newNotebookModal");
    els.recallModal = document.getElementById("recallModal");
    els.vaultModal = document.getElementById("vaultModal");
    els.syncModal = document.getElementById("syncModal");
    els.audioDeckBar = document.getElementById("audioDeckBar");
    els.textbookPreview = document.getElementById("textbookPreview");
    els.ankiModal = document.getElementById("ankiModal");
    els.obsidianModal = document.getElementById("obsidianModal");

    bindTopAndToolbarEvents();
    bindInkCanvasEvents();
    bindModalEvents();
    bindVaultAndAudioEvents();
    bindAnkiAndObsidianEvents();
    loadSavedLibrary();
    window.addEventListener("pagehide", () => {
      if (saveTimer) saveLibrary();
    });
    renderAll();
  }

  function renderAll() {
    renderFolderTree();
    renderSidebar();
    renderPaperSheet();
    renderFollowerDock();
    renderAudioDeckBar();
  }

  function getAllFolderPaths() {
    const set = new Set(state.customFolders);
    for (const nb of state.notebooks) {
      if (nb.folderPath) {
        const parts = nb.folderPath.split("/").filter(Boolean);
        let acc = "";
        for (const p of parts) {
          acc = acc ? `${acc}/${p}` : p;
          set.add(acc);
        }
      }
    }
    return Array.from(set).sort();
  }

  function renderFolderTree() {
    if (!els.folderTree) return;
    els.folderTree.innerHTML = "";
    const allRow = document.createElement("div");
    allRow.className = "folder-item" + (state.activeFolder === "" ? " active" : "");
    allRow.innerHTML = `<span>All Logs</span><span class="folder-count">${state.notebooks.length}</span>`;
    allRow.addEventListener("click", () => {
      state.activeFolder = "";
      renderAll();
    });
    els.folderTree.appendChild(allRow);

    for (const folder of getAllFolderPaths()) {
      const depth = folder.split("/").length - 1;
      const count = state.notebooks.filter(
        (n) => n.folderPath === folder || (n.folderPath && n.folderPath.startsWith(folder + "/"))
      ).length;
      const row = document.createElement("div");
      row.className = "folder-item" + (state.activeFolder === folder ? " active" : "");
      row.style.paddingLeft = `${9 + depth * 12}px`;
      const leaf = folder.split("/").pop();
      row.innerHTML = `<span>${depth > 0 ? "↳ " : "📁 "}${escapeHTML(leaf)}</span><span class="folder-count">${count}</span>`;
      row.addEventListener("click", () => {
        state.activeFolder = folder;
        renderAll();
      });
      els.folderTree.appendChild(row);
    }
  }

  function renderSidebar() {
    const activeNb = getActiveNotebook();
    els.activeNotebookCrumb.textContent = activeNb.title;
    scheduleSave();

    const visibleNotebooks = state.activeFolder
      ? state.notebooks.filter(
          (n) => n.folderPath === state.activeFolder || (n.folderPath && n.folderPath.startsWith(state.activeFolder + "/"))
        )
      : state.notebooks;

    els.notebookList.innerHTML = "";
    visibleNotebooks.forEach((nb) => {
      const item = document.createElement("div");
      item.className = "notebook-item" + (nb.id === activeNb.id ? " active" : "");
      item.innerHTML = `
        <div class="notebook-mini-cover" style="background:${nb.coverColor}"></div>
        <div class="notebook-meta">
          <div class="notebook-name">${escapeHTML(nb.title)}</div>
          <div class="notebook-sub">${escapeHTML(nb.folderPath || nb.subtitle)}</div>
        </div>
      `;
      item.addEventListener("click", () => {
        state.activeNotebookId = nb.id;
        state.activeLineIndex = 0;
        renderAll();
      });
      els.notebookList.appendChild(item);
    });

    // Paper style chips
    const styles = [
      { id: "ruled", label: "Ruled" },
      { id: "dottedLined", label: "Dotted-Lined" },
      { id: "grid", label: "Grid" },
      { id: "dotted", label: "Dotted" },
      { id: "blank", label: "Blank" }
    ];
    els.paperStyleChips.innerHTML = "";
    styles.forEach((st) => {
      const chip = document.createElement("button");
      chip.className = "paper-chip" + (activeNb.paperStyle === st.id ? " active" : "");
      chip.textContent = st.label;
      chip.addEventListener("click", () => {
        activeNb.paperStyle = st.id;
        renderPaperSheet();
        renderSidebar();
      });
      els.paperStyleChips.appendChild(chip);
    });
  }

  function renderPaperSheet() {
    const nb = getActiveNotebook();
    els.paperSheet.className = `paper-sheet paper-${nb.paperStyle}`;
    els.pageTitleInput.value = nb.title;

    // Ensure at least 12 lines so it feels like a full ruled sheet
    while (nb.lines.length < 12) {
      nb.lines.push("");
    }

    const annotations = WorkChecker.checkLines(nb.lines, state.activeLineIndex);
    updatePageStatusSummary(annotations);

    // Rebuild or update rows while preserving cursor focus if user is typing
    const existingRows = els.workLinesContainer.querySelectorAll(".work-line-row");
    if (existingRows.length !== nb.lines.length) {
      els.workLinesContainer.innerHTML = "";
      nb.lines.forEach((lineText, idx) => {
        const row = createWorkLineRow(idx, lineText);
        els.workLinesContainer.appendChild(row);
      });
    }

    // Apply annotations to each row
    const rows = els.workLinesContainer.querySelectorAll(".work-line-row");
    rows.forEach((row, idx) => {
      const ann = annotations[idx];
      const input = row.querySelector(".work-line-input");
      if (document.activeElement !== input && input.value !== nb.lines[idx]) {
        input.value = nb.lines[idx];
      }

      row.classList.toggle("focused", state.followerEnabled && idx === state.activeLineIndex);
      row.classList.toggle(
        "is-slip",
        state.followerEnabled && ann.feedback.kind === "needsAttention"
      );
      row.classList.toggle(
        "is-verified",
        state.followerEnabled && ann.feedback.kind === "verified"
      );

      const badgeSlot = row.querySelector(".badge-slot");
      badgeSlot.innerHTML = "";

      if (state.followerEnabled && nb.lines[idx].trim().length > 0) {
        const badge = buildMarginBadge(ann, idx);
        if (badge) badgeSlot.appendChild(badge);
      }
    });

    resizeAndRedrawInkCanvas();
    renderAttachmentsStrip();
    renderTextbookPreviewIfActive();
    scheduleSave();
  }

  function renderAttachmentsStrip() {
    if (!els.pageAttachmentsStrip) return;
    const nb = getActiveNotebook();
    const list = nb.attachments || [];
    if (list.length === 0) {
      els.pageAttachmentsStrip.style.display = "none";
      els.pageAttachmentsStrip.innerHTML = "";
      return;
    }
    els.pageAttachmentsStrip.style.display = "flex";
    els.pageAttachmentsStrip.innerHTML = "";
    list.forEach((att) => {
      const chip = document.createElement("button");
      chip.className = "attachment-chip";
      const icon = att.kind === "image" ? "🖼" : att.kind === "audio" ? "♫" : att.kind === "video" ? "🎬" : "📄";
      chip.innerHTML = `<span>${icon}</span><span>${escapeHTML(att.title)}</span>`;
      chip.addEventListener("click", () => {
        if (att.kind === "audio") {
          playAudioAttachment(att);
        } else {
          openVaultAndPreview(att);
        }
      });
      els.pageAttachmentsStrip.appendChild(chip);
    });
  }

  function createWorkLineRow(idx, lineText) {
    const row = document.createElement("div");
    row.className = "work-line-row";
    row.innerHTML = `
      <span class="line-number-tag">${idx + 1}</span>
      <div class="line-follower-bar"></div>
      <input
        type="text"
        class="work-line-input"
        value="${escapeAttr(lineText)}"
        placeholder="${idx === 0 ? "Write an equation, derivation step, or note…" : ""}"
        aria-label="Work line ${idx + 1}"
      />
      <div class="badge-slot"></div>
    `;

    const input = row.querySelector(".work-line-input");
    input.addEventListener("focus", () => {
      state.activeLineIndex = idx;
      renderPaperSheet();
      renderFollowerDock();
    });

    input.addEventListener("input", (e) => {
      const nb = getActiveNotebook();
      nb.lines[idx] = e.target.value;
      state.activeLineIndex = idx;

      // Move live pen follower dot along with typing caret
      const rect = input.getBoundingClientRect();
      const sheetRect = els.paperSheet.getBoundingClientRect();
      const charWidth = 10.6;
      const caretX = Math.min(rect.width - 20, (e.target.selectionStart || e.target.value.length) * charWidth);
      showPenFollowerDot(rect.left - sheetRect.left + caretX + 6, rect.top - sheetRect.top + rect.height * 0.55);

      renderPaperSheet();
      renderFollowerDock();
    });

    input.addEventListener("keydown", (e) => {
      const nb = getActiveNotebook();
      if (e.key === "Enter") {
        e.preventDefault();
        const nextIdx = idx + 1;
        if (nextIdx >= nb.lines.length) {
          nb.lines.push("");
        }
        state.activeLineIndex = nextIdx;
        renderPaperSheet();
        renderFollowerDock();
        const inputs = els.workLinesContainer.querySelectorAll(".work-line-input");
        if (inputs[nextIdx]) inputs[nextIdx].focus();
      } else if (e.key === "ArrowDown") {
        const inputs = els.workLinesContainer.querySelectorAll(".work-line-input");
        if (inputs[idx + 1]) {
          e.preventDefault();
          inputs[idx + 1].focus();
        }
      } else if (e.key === "ArrowUp") {
        const inputs = els.workLinesContainer.querySelectorAll(".work-line-input");
        if (inputs[idx - 1]) {
          e.preventDefault();
          inputs[idx - 1].focus();
        }
      }
    });

    return row;
  }

  function buildMarginBadge(ann, idx) {
    const fb = ann.feedback;
    if (fb.kind === "tracking") return null;

    const badge = document.createElement("div");
    if (fb.kind === "verified") {
      badge.className = "margin-badge badge-verified";
      const label = fb.expectedValue ? `✓ ${fb.expectedValue}` : "✓ Verified";
      badge.innerHTML = `<span>${escapeHTML(label)}</span>`;
      badge.title = fb.message;
      badge.addEventListener("click", () => {
        state.activeLineIndex = idx;
        state.inspectorOpen = true;
        renderPaperSheet();
        renderFollowerDock();
      });
      return badge;
    }

    if (fb.kind === "needsAttention") {
      badge.className = "margin-badge badge-slip";
      const shortHint = fb.expectedValue ? `⚠ Check → ${fb.expectedValue}` : `⚠ ${fb.message}`;
      badge.innerHTML = `<span>${escapeHTML(shortHint)}</span>`;
      if (fb.replacementText) {
        const fixBtn = document.createElement("button");
        fixBtn.className = "badge-fix-btn";
        fixBtn.textContent = "Fix";
        fixBtn.addEventListener("click", (e) => {
          e.stopPropagation();
          applyLineCorrection(idx, fb.replacementText);
        });
        badge.appendChild(fixBtn);
      }
      badge.addEventListener("click", () => {
        state.activeLineIndex = idx;
        state.inspectorOpen = true;
        renderPaperSheet();
        renderFollowerDock();
      });
      return badge;
    }

    if (fb.kind === "evaluated") {
      badge.className = "margin-badge badge-evaluated";
      badge.innerHTML = `<span>= ${escapeHTML(fb.expectedValue || "")}</span>`;
      if (fb.replacementText) {
        const addBtn = document.createElement("button");
        addBtn.className = "badge-add-btn";
        addBtn.textContent = "+ Add";
        addBtn.addEventListener("click", (e) => {
          e.stopPropagation();
          applyLineCorrection(idx, fb.replacementText);
        });
        badge.appendChild(addBtn);
      }
      return badge;
    }

    return null;
  }

  // Writes every line back into its row. renderPaperSheet leaves the focused row alone so typing
  // isn't interrupted, but a Fix or Insert button has to change that row too, and in Safari
  // clicking a button doesn't move focus off the line.
  function refreshLineInputs() {
    const nb = getActiveNotebook();
    els.workLinesContainer.querySelectorAll(".work-line-input").forEach((input, idx) => {
      if (idx < nb.lines.length && input.value !== nb.lines[idx]) input.value = nb.lines[idx];
    });
  }

  function applyLineCorrection(idx, replacementText) {
    const nb = getActiveNotebook();
    nb.lines[idx] = replacementText;
    state.activeLineIndex = idx;
    renderPaperSheet();
    refreshLineInputs();
    renderFollowerDock();
  }

  function updatePageStatusSummary(annotations) {
    const verifiedCount = annotations.filter((a) => a.feedback.kind === "verified").length;
    const slipCount = annotations.filter((a) => a.feedback.kind === "needsAttention").length;
    const evalCount = annotations.filter((a) => a.feedback.kind === "evaluated").length;

    if (!state.followerEnabled) {
      els.pageStatusSummary.innerHTML = `<span style="color:var(--muted)">Work Follower paused</span>`;
      return;
    }

    els.pageStatusSummary.innerHTML = `
      <span style="color:var(--verified)">✓ ${verifiedCount} verified</span>
      <span>·</span>
      <span style="color:${slipCount > 0 ? "var(--slip)" : "var(--muted)"}">⚠ ${slipCount} ${slipCount === 1 ? "slip" : "slips"}</span>
      ${evalCount > 0 ? `<span>·</span><span style="color:var(--accent)">= ${evalCount} ready</span>` : ""}
    `;
  }

  function renderFollowerDock() {
    if (!state.followerEnabled) {
      els.floatingFollowerDock.style.display = "none";
      els.toggleFollowerBtn.classList.remove("active");
      return;
    }
    els.floatingFollowerDock.style.display = "flex";
    els.toggleFollowerBtn.classList.add("active");

    const nb = getActiveNotebook();
    const annotations = WorkChecker.checkLines(nb.lines, state.activeLineIndex);
    const activeAnn =
      annotations[state.activeLineIndex] ||
      annotations.find((a) => a.feedback.kind === "needsAttention") ||
      annotations[0];

    const fb = activeAnn ? activeAnn.feedback : { kind: "tracking", category: "general", message: "Following your work…" };
    els.followerPill.className =
      "follower-pill" +
      (fb.kind === "needsAttention" ? " pill-slip" : fb.kind === "verified" ? " pill-verified" : "");

    const catColors = {
      algebra: { bg: "rgba(10, 96, 255, 0.12)", fg: "var(--accent)", label: "Algebra" },
      arithmetic: { bg: "rgba(46, 148, 82, 0.14)", fg: "var(--verified)", label: "Math" },
      style: { bg: "rgba(139, 74, 46, 0.14)", fg: "var(--terracotta)", label: "Style Guide" },
      general: { bg: "rgba(91, 98, 114, 0.12)", fg: "var(--muted)", label: "Line " + ((activeAnn ? activeAnn.index : 0) + 1) }
    };
    const cat = catColors[fb.category] || catColors.general;

    let actionHTML = "";
    if (fb.replacementText && activeAnn) {
      const btnColor = fb.kind === "needsAttention" ? "var(--slip)" : "var(--accent)";
      const btnLabel = fb.kind === "needsAttention" ? "Fix Line" : `Insert = ${fb.expectedValue || ""}`;
      actionHTML = `<button class="pill-action-btn" id="pillQuickFixBtn" style="background:${btnColor}">${escapeHTML(btnLabel)}</button>`;
    }

    els.followerPill.innerHTML = `
      <span class="pill-category-tag" style="background:${cat.bg};color:${cat.fg}">${escapeHTML(cat.label)}</span>
      <span class="pill-message">${escapeHTML(fb.message)}</span>
      ${actionHTML}
      <button class="btn" id="pillInspectBtn" style="padding:4px 10px;font-size:11px">Step Log (${annotations.filter((a) => a.text.trim()).length})</button>
    `;

    const quickFixBtn = document.getElementById("pillQuickFixBtn");
    if (quickFixBtn && activeAnn && fb.replacementText) {
      quickFixBtn.addEventListener("click", () => {
        applyLineCorrection(activeAnn.index, fb.replacementText);
      });
    }

    const inspectBtn = document.getElementById("pillInspectBtn");
    if (inspectBtn) {
      inspectBtn.addEventListener("click", () => {
        state.inspectorOpen = !state.inspectorOpen;
        renderFollowerDock();
      });
    }

    // Populate Step Inspector Popover
    els.stepInspectorPopover.classList.toggle("open", state.inspectorOpen);
    if (state.inspectorOpen) {
      els.stepLogList.innerHTML = "";
      annotations
        .filter((a) => a.text.trim().length > 0)
        .forEach((ann) => {
          const item = document.createElement("div");
          item.className = "step-log-item";
          const icon =
            ann.feedback.kind === "verified"
              ? `<span style="color:var(--verified);font-weight:700">✓</span>`
              : ann.feedback.kind === "needsAttention"
              ? `<span style="color:var(--slip);font-weight:700">⚠</span>`
              : ann.feedback.kind === "evaluated"
              ? `<span style="color:var(--accent);font-weight:700">=</span>`
              : `<span style="color:var(--muted)">•</span>`;
          item.innerHTML = `
            <div style="display:flex;align-items:center;gap:8px;min-width:0">
              ${icon}
              <div style="min-width:0">
                <div style="font-family:monospace;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">L${ann.index + 1}: ${escapeHTML(ann.text)}</div>
                <div style="color:var(--muted);font-size:11px">${escapeHTML(ann.feedback.message)}</div>
              </div>
            </div>
          `;
          if (ann.feedback.replacementText) {
            const btn = document.createElement("button");
            btn.className = "badge-fix-btn";
            btn.style.background = ann.feedback.kind === "needsAttention" ? "var(--slip)" : "var(--accent)";
            btn.textContent = ann.feedback.kind === "needsAttention" ? "Fix" : "Apply";
            btn.addEventListener("click", () => {
              applyLineCorrection(ann.index, ann.feedback.replacementText);
            });
            item.appendChild(btn);
          }
          els.stepLogList.appendChild(item);
        });
    }
  }

  // ============================================================================
  // 6. Freehand Ink Canvas + Scratch-Out Erase + Shape Snap + Live Pen Dot
  // ============================================================================
  let isDrawing = false;
  let currentStroke = null;
  let dotHideTimer = null;

  function showPenFollowerDot(x, y) {
    if (!state.followerEnabled) return;
    els.penFollowerDot.style.left = `${x}px`;
    els.penFollowerDot.style.top = `${y}px`;
    els.penFollowerDot.classList.add("visible");
    clearTimeout(dotHideTimer);
    dotHideTimer = setTimeout(() => {
      els.penFollowerDot.classList.remove("visible");
    }, 1100);
  }

  function resizeAndRedrawInkCanvas() {
    const canvas = els.inkCanvas;
    if (!canvas) return;
    const rect = els.paperSheet.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    if (canvas.width !== Math.round(rect.width * dpr) || canvas.height !== Math.round(rect.height * dpr)) {
      canvas.width = Math.round(rect.width * dpr);
      canvas.height = Math.round(rect.height * dpr);
    }
    canvas.classList.toggle("passthrough", state.activeTool === "type");
    // The line rows sit above the canvas; while a drawing tool is active they let the pen through.
    els.paperSheet.classList.toggle("drawing", state.activeTool !== "type");
    redrawStrokes();
  }

  function redrawStrokes() {
    const canvas = els.inkCanvas;
    const ctx = canvas.getContext("2d");
    const dpr = window.devicePixelRatio || 1;
    ctx.save();
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, canvas.width / dpr, canvas.height / dpr);

    const nb = getActiveNotebook();
    const allStrokes = currentStroke ? [...nb.strokes, currentStroke] : nb.strokes;

    for (const st of allStrokes) {
      if (!st.points || st.points.length < 2) continue;
      ctx.save();
      ctx.beginPath();
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      ctx.strokeStyle = st.color;
      ctx.lineWidth = st.width;
      ctx.globalAlpha = st.alpha || 1.0;

      ctx.moveTo(st.points[0].x, st.points[0].y);
      for (let i = 1; i < st.points.length; i++) {
        const prev = st.points[i - 1];
        const curr = st.points[i];
        const midX = (prev.x + curr.x) / 2;
        const midY = (prev.y + curr.y) / 2;
        ctx.quadraticCurveTo(prev.x, prev.y, midX, midY);
      }
      const last = st.points[st.points.length - 1];
      ctx.lineTo(last.x, last.y);
      ctx.stroke();
      ctx.restore();
    }
    ctx.restore();
  }

  function bindInkCanvasEvents() {
    const canvas = els.inkCanvas;
    window.addEventListener("resize", resizeAndRedrawInkCanvas);

    canvas.addEventListener("pointerdown", (e) => {
      if (state.activeTool === "type") return;
      try {
        canvas.setPointerCapture(e.pointerId);
      } catch (_) {
        // Capture is a nicety (keeps the stroke going outside the sheet); drawing works without it.
      }
      const rect = canvas.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;

      // Update active line row based on pen Y coordinate
      const lineIdx = Math.max(0, Math.min(getActiveNotebook().lines.length - 1, Math.floor((y - 110) / 44)));
      state.activeLineIndex = lineIdx;
      showPenFollowerDot(x, y);

      if (state.activeTool === "eraser") {
        eraseStrokeNear(x, y);
        isDrawing = true;
        return;
      }

      isDrawing = true;
      currentStroke = {
        tool: state.activeTool,
        color: state.inkColor,
        width: state.activeTool === "highlighter" ? 18 : 2.8,
        alpha: state.activeTool === "highlighter" ? 0.28 : 1.0,
        points: [{ x, y, t: performance.now() }]
      };
      redrawStrokes();
      renderPaperSheet();
      renderFollowerDock();
    });

    canvas.addEventListener("pointermove", (e) => {
      if (!isDrawing) return;
      const rect = canvas.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      showPenFollowerDot(x, y);

      if (state.activeTool === "eraser") {
        eraseStrokeNear(x, y);
        return;
      }
      if (currentStroke) {
        currentStroke.points.push({ x, y, t: performance.now() });
        redrawStrokes();
      }
    });

    const finishStroke = () => {
      if (!isDrawing) return;
      isDrawing = false;
      if (currentStroke && currentStroke.points.length >= 2) {
        const nb = getActiveNotebook();
        // Check for MyScript-style zig-zag scratch-out gesture
        if (isScratchOutGesture(currentStroke.points)) {
          const box = getStrokeBox(currentStroke.points);
          nb.strokes = nb.strokes.filter((s) => !boxesOverlap(box, getStrokeBox(s.points)));
        } else {
          nb.strokes.push(currentStroke);
        }
      }
      currentStroke = null;
      redrawStrokes();
      scheduleSave();
    };
    canvas.addEventListener("pointerup", finishStroke);
    // Without these a cancelled touch (palm, system gesture) leaves the pen "down", and the next
    // hover keeps adding to the stroke.
    canvas.addEventListener("pointercancel", finishStroke);
    canvas.addEventListener("lostpointercapture", finishStroke);
  }

  function eraseStrokeNear(x, y) {
    const nb = getActiveNotebook();
    const before = nb.strokes.length;
    nb.strokes = nb.strokes.filter((st) => !st.points.some((p) => Math.hypot(p.x - x, p.y - y) < 18));
    if (nb.strokes.length !== before) {
      redrawStrokes();
      scheduleSave();
    }
  }

  function isScratchOutGesture(pts) {
    if (pts.length < 18) return false;
    let signFlips = 0;
    let lastDxSign = 0;
    for (let i = 2; i < pts.length; i++) {
      const dx = pts[i].x - pts[i - 2].x;
      if (Math.abs(dx) < 6) continue;
      const sign = dx > 0 ? 1 : -1;
      if (lastDxSign !== 0 && sign !== lastDxSign) signFlips++;
      lastDxSign = sign;
    }
    return signFlips >= 4;
  }

  function getStrokeBox(pts) {
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const p of pts) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    return { minX, minY, maxX, maxY };
  }

  function boxesOverlap(a, b) {
    return a.minX <= b.maxX && a.maxX >= b.minX && a.minY <= b.maxY && a.maxY >= b.minY;
  }

  // ============================================================================
  // 7. Toolbar, Top Actions, New Notebook 2-Pane Modal & Active Recall Modal
  // ============================================================================
  function bindTopAndToolbarEvents() {
    els.pageTitleInput.addEventListener("input", (e) => {
      const nb = getActiveNotebook();
      nb.title = e.target.value || "Untitled Notebook";
      renderSidebar();
    });

    // Tool buttons
    document.querySelectorAll("[data-tool]").forEach((btn) => {
      btn.addEventListener("click", () => {
        state.activeTool = btn.getAttribute("data-tool");
        document.querySelectorAll("[data-tool]").forEach((b) => b.classList.toggle("active", b === btn));
        resizeAndRedrawInkCanvas();
      });
    });

    // Color swatches
    document.querySelectorAll("[data-ink-color]").forEach((sw) => {
      sw.addEventListener("click", () => {
        state.inkColor = sw.getAttribute("data-ink-color");
        document.querySelectorAll("[data-ink-color]").forEach((s) => s.classList.toggle("active", s === sw));
      });
    });

    // Clear ink button
    document.getElementById("clearInkBtn").addEventListener("click", () => {
      getActiveNotebook().strokes = [];
      redrawStrokes();
      scheduleSave();
    });

    // Toggle Live Work Follower button
    els.toggleFollowerBtn.addEventListener("click", () => {
      state.followerEnabled = !state.followerEnabled;
      renderPaperSheet();
      renderFollowerDock();
    });

    // Add Line button
    document.getElementById("addLineBtn").addEventListener("click", () => {
      const nb = getActiveNotebook();
      nb.lines.push("");
      state.activeLineIndex = nb.lines.length - 1;
      renderPaperSheet();
      const inputs = els.workLinesContainer.querySelectorAll(".work-line-input");
      if (inputs[state.activeLineIndex]) inputs[state.activeLineIndex].focus();
    });

    // Fix All Slips button
    document.getElementById("fixAllSlipsBtn").addEventListener("click", () => {
      const nb = getActiveNotebook();
      // Iteratively fix up to 5 passes so multi-step dependencies cascade cleanly
      for (let pass = 0; pass < 5; pass++) {
        const anns = WorkChecker.checkLines(nb.lines, state.activeLineIndex);
        const slip = anns.find((a) => a.feedback.kind === "needsAttention" && a.feedback.replacementText);
        if (!slip) break;
        nb.lines[slip.index] = slip.feedback.replacementText;
      }
      renderPaperSheet();
      refreshLineInputs();
      renderFollowerDock();
    });
  }

  function bindModalEvents() {
    // New Notebook 2-Pane Modal
    const openNewBtn = document.getElementById("openNewNotebookBtn");
    const closeNewBtn = document.getElementById("closeNewNotebookBtn");
    const createNewBtn = document.getElementById("createNotebookConfirmBtn");
    const newTitleInput = document.getElementById("newNotebookTitleInput");
    const cover3DBook = document.getElementById("cover3DBook");
    const cover3DTitle = document.getElementById("cover3DTitle");

    openNewBtn.addEventListener("click", () => {
      newTitleInput.value = "Engineering Statics";
      cover3DTitle.textContent = newTitleInput.value;
      els.newNotebookModal.classList.add("open");
    });

    closeNewBtn.addEventListener("click", () => {
      els.newNotebookModal.classList.remove("open");
    });

    newTitleInput.addEventListener("input", () => {
      cover3DTitle.textContent = newTitleInput.value || "Untitled";
    });

    document.querySelectorAll("[data-cover-color]").forEach((btn) => {
      btn.addEventListener("click", () => {
        state.newModalCoverColor = btn.getAttribute("data-cover-color");
        cover3DBook.style.background = state.newModalCoverColor;
        document.querySelectorAll("[data-cover-color]").forEach((b) => b.classList.toggle("active", b === btn));
      });
    });

    document.querySelectorAll("[data-modal-paper]").forEach((btn) => {
      btn.addEventListener("click", () => {
        state.newModalPaperStyle = btn.getAttribute("data-modal-paper");
        document.querySelectorAll("[data-modal-paper]").forEach((b) => b.classList.toggle("active", b === btn));
      });
    });

    createNewBtn.addEventListener("click", () => {
      const id = "nb-" + Date.now();
      const title = newTitleInput.value.trim() || "Untitled Log";
      const folderInput = document.getElementById("newNotebookFolderInput");
      const folderPath = (folderInput ? folderInput.value.trim() : "") || state.activeFolder;
      state.notebooks.unshift({
        id,
        title,
        subtitle: "Custom log",
        folderPath,
        coverColor: state.newModalCoverColor,
        paperStyle: state.newModalPaperStyle,
        lines: [
          `${title} — Problem Set`,
          "2x + 10 = 26",
          "2x = 16",
          "x = 8",
          ""
        ],
        strokes: [],
        attachments: []
      });
      state.activeNotebookId = id;
      state.activeLineIndex = 1;
      els.newNotebookModal.classList.remove("open");
      renderAll();
    });

    // Active Recall Practice Modal
    const openRecallBtn = document.getElementById("openRecallBtn");
    const closeRecallBtn = document.getElementById("closeRecallBtn");
    const recallOriginalBox = document.getElementById("recallOriginalBox");
    const recallAttemptInput = document.getElementById("recallAttemptInput");
    const recallSummarySlot = document.getElementById("recallSummarySlot");

    function updateRecallComparison() {
      const nb = getActiveNotebook();
      const originalText = nb.lines.filter((l) => l.trim().length > 0).join("\n");
      const summary = WorkChecker.compareRecall(originalText, recallAttemptInput.value);

      const scoreColor =
        summary.accuracyPercent >= 80
          ? "var(--verified)"
          : summary.accuracyPercent >= 50
          ? "var(--accent)"
          : "var(--slip)";

      recallSummarySlot.innerHTML = `
        <div class="recall-summary-card">
          <div style="display:flex;align-items:center;justify-content:space-between">
            <div style="font-weight:700;font-size:14px;color:${scoreColor}">
              ✓ Work Checker Recall Score: ${summary.accuracyPercent}%
            </div>
            <span style="font-size:12px;font-weight:700;padding:3px 10px;border-radius:999px;background:rgba(10,96,255,0.1);color:var(--accent)">
              Suggested Rating: ${summary.suggestedRating} / 5 ★
            </span>
          </div>
          ${
            summary.matchedTerms.length > 0
              ? `<div>
                  <div style="font-size:11px;font-weight:700;color:var(--muted);margin-bottom:4px">KEY CONCEPTS RECALLED (${summary.matchedTerms.length})</div>
                  <div class="term-chips">
                    ${summary.matchedTerms.map((t) => `<span class="term-chip" style="background:var(--verified-bg);color:var(--verified)">✓ ${escapeHTML(t)}</span>`).join("")}
                  </div>
                </div>`
              : ""
          }
          ${
            summary.missedTerms.length > 0
              ? `<div>
                  <div style="font-size:11px;font-weight:700;color:var(--muted);margin-bottom:4px">MISSED CONCEPTS TO REVIEW (${summary.missedTerms.length})</div>
                  <div class="term-chips">
                    ${summary.missedTerms.map((t) => `<span class="term-chip" style="background:var(--slip-bg);color:var(--slip)">+ ${escapeHTML(t)}</span>`).join("")}
                  </div>
                </div>`
              : ""
          }
          ${
            summary.verifiedEquations.length > 0
              ? `<div style="font-size:12px;color:var(--verified);font-weight:600">✓ Math verified in recall: ${summary.verifiedEquations.map(escapeHTML).join(" · ")}</div>`
              : ""
          }
          ${
            summary.mathSlips.length > 0
              ? `<div style="font-size:12px;color:var(--slip);font-weight:600">⚠ Math slip in recall: ${summary.mathSlips.map(escapeHTML).join(" · ")}</div>`
              : ""
          }
        </div>
      `;
    }

    openRecallBtn.addEventListener("click", () => {
      const nb = getActiveNotebook();
      const nonEmpty = nb.lines.filter((l) => l.trim().length > 0);
      recallOriginalBox.textContent = nonEmpty.join("\n");
      // Pre-fill a sample recall attempt so the user sees immediate live grading
      recallAttemptInput.value = nonEmpty.slice(0, Math.max(1, Math.ceil(nonEmpty.length * 0.65))).join("\n");
      updateRecallComparison();
      els.recallModal.classList.add("open");
    });

    closeRecallBtn.addEventListener("click", () => {
      els.recallModal.classList.remove("open");
    });

    recallAttemptInput.addEventListener("input", updateRecallComparison);
  }

  // ============================================================================
  // 8. BelloBook + Amphi Features: Folders, Media Vault, Audio Deck, Export, Sync
  // ============================================================================
  let htmlAudio = null;
  let synthTimer = null;
  let synthContext = null;

  function playAudioAttachment(att) {
    const idx = state.audioQueue.findIndex((a) => a.id === att.id);
    if (idx >= 0) {
      state.audioIndex = idx;
    } else {
      state.audioQueue.push(att);
      state.audioIndex = state.audioQueue.length - 1;
    }
    startCurrentAudioTrack();
  }

  function startCurrentAudioTrack() {
    const track = state.audioQueue[state.audioIndex];
    if (!track) return;
    stopRawAudio();

    if (track.dataUrl) {
      htmlAudio = new Audio(track.dataUrl);
      htmlAudio.onended = () => {
        if (state.audioQueue.length > 1) {
          state.audioIndex = (state.audioIndex + 1) % state.audioQueue.length;
          startCurrentAudioTrack();
        } else {
          state.audioPlaying = false;
          renderAudioDeckBar();
        }
      };
      htmlAudio.play().catch(() => {});
      state.audioPlaying = true;
    } else if (track.isDemoSynth && (window.AudioContext || window.webkitAudioContext)) {
      // Gentle Web Audio API chord chime so the built-in sample track works offline
      try {
        // Browsers allow only a handful of audio contexts per page, so keep one and reuse it.
        if (!synthContext) synthContext = new (window.AudioContext || window.webkitAudioContext)();
        const ctx = synthContext;
        if (ctx.state === "suspended") ctx.resume();
        const notes = [261.63, 329.63, 392.0, 523.25];
        notes.forEach((freq, i) => {
          const osc = ctx.createOscillator();
          const gain = ctx.createGain();
          osc.type = "sine";
          osc.frequency.value = freq;
          gain.gain.setValueAtTime(0.001, ctx.currentTime + i * 0.12);
          gain.gain.exponentialRampToValueAtTime(0.06, ctx.currentTime + i * 0.12 + 0.08);
          gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + i * 0.12 + 1.4);
          osc.connect(gain);
          gain.connect(ctx.destination);
          osc.start(ctx.currentTime + i * 0.12);
          osc.stop(ctx.currentTime + i * 0.12 + 1.45);
        });
        state.audioPlaying = true;
        synthTimer = setTimeout(() => {
          state.audioPlaying = false;
          renderAudioDeckBar();
        }, 1800);
      } catch (_) {
        state.audioPlaying = false;
      }
    }
    renderAudioDeckBar();
  }

  function stopRawAudio() {
    if (htmlAudio) {
      htmlAudio.pause();
      htmlAudio = null;
    }
    if (synthTimer) {
      clearTimeout(synthTimer);
      synthTimer = null;
    }
  }

  function renderAudioDeckBar() {
    if (!els.audioDeckBar) return;
    const track = state.audioQueue[state.audioIndex];
    if (!track) {
      els.audioDeckBar.classList.remove("visible");
      return;
    }
    els.audioDeckBar.classList.add("visible");
    document.getElementById("audioDeckTitle").textContent = track.title;
    document.getElementById("audioDeckSub").textContent = track.artist
      ? `${track.artist}${track.album ? " · " + track.album : ""}`
      : "BelloBook Audio Deck";
    document.getElementById("audioPlayPauseBtn").textContent = state.audioPlaying ? "⏸" : "▶";
  }

  function openVaultAndPreview(att) {
    renderVaultGrid();
    els.vaultModal.classList.add("open");
    if (att) showVaultPreview(att);
  }

  function showVaultPreview(att) {
    const pane = document.getElementById("vaultPreviewPane");
    const title = document.getElementById("vaultPreviewTitle");
    const body = document.getElementById("vaultPreviewBody");
    pane.style.display = "flex";
    title.textContent = `Quick Preview — ${att.title}`;
    body.innerHTML = "";

    if (att.kind === "image" && att.dataUrl) {
      body.innerHTML = `<img src="${escapeAttr(att.dataUrl)}" alt="${escapeAttr(att.title)}" style="max-width:100%;border-radius:8px" />`;
    } else if (att.kind === "video" && att.dataUrl) {
      body.innerHTML = `<video src="${escapeAttr(att.dataUrl)}" controls style="max-width:100%;border-radius:8px"></video>`;
    } else if (att.dataUrl && att.dataUrl.startsWith("data:application/pdf")) {
      body.innerHTML = `<iframe src="${escapeAttr(att.dataUrl)}" style="width:100%;height:250px;border:none;border-radius:8px"></iframe>`;
    } else if (att.textPreview) {
      body.innerHTML = `<pre style="margin:0;font-family:monospace;font-size:12.5px;white-space:pre-wrap">${escapeHTML(att.textPreview)}</pre>`;
    } else {
      body.innerHTML = `<div style="font-size:12.5px;color:var(--muted)">Stored in BelloBook Vault (${escapeHTML(att.filename)}).</div>`;
    }
  }

  function renderVaultGrid() {
    const grid = document.getElementById("vaultGrid");
    if (!grid) return;
    const nb = getActiveNotebook();
    const list = nb.attachments || [];
    grid.innerHTML = "";

    if (list.length === 0) {
      grid.innerHTML = `<div style="grid-column:1/-1;padding:24px;text-align:center;color:var(--muted);font-size:13px">No attachments on this notebook yet. Attach photos, audio, videos, PDFs, or Markdown files above.</div>`;
      return;
    }

    list.forEach((att, idx) => {
      const card = document.createElement("div");
      card.className = "vault-card";
      const icon = att.kind === "image" ? "🖼" : att.kind === "audio" ? "♫" : att.kind === "video" ? "🎬" : "📄";
      const thumb =
        att.kind === "image" && att.dataUrl
          ? `<img src="${escapeAttr(att.dataUrl)}" alt="${escapeAttr(att.title)}" />`
          : `<span>${icon}</span>`;

      card.innerHTML = `
        <div class="vault-thumb">${thumb}</div>
        <div style="font-size:13px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${escapeHTML(att.title)}</div>
        <div style="font-size:11px;color:var(--muted)">${escapeHTML(att.artist || att.kind.toUpperCase())}</div>
        <div style="display:flex;gap:6px;margin-top:auto">
          <button class="btn" data-vault-action="primary" style="flex:1;justify-content:center;padding:4px 8px;font-size:11px">${att.kind === "audio" ? "Play" : "Preview"}</button>
          <button class="btn" data-vault-action="remove" style="padding:4px 8px;font-size:11px;color:var(--slip)">✕</button>
        </div>
      `;

      card.querySelector('[data-vault-action="primary"]').addEventListener("click", () => {
        if (att.kind === "audio") playAudioAttachment(att);
        else showVaultPreview(att);
      });
      card.querySelector('[data-vault-action="remove"]').addEventListener("click", () => {
        nb.attachments.splice(idx, 1);
        // Take it off the Audio Deck too, so a removed track can't keep playing or come back round.
        const queued = state.audioQueue.findIndex((a) => a.id === att.id);
        if (queued >= 0) {
          const wasCurrent = queued === state.audioIndex;
          state.audioQueue.splice(queued, 1);
          if (wasCurrent) {
            stopRawAudio();
            state.audioPlaying = false;
            state.audioIndex = -1;
          } else if (queued < state.audioIndex) {
            state.audioIndex -= 1;
          }
          renderAudioDeckBar();
        }
        renderVaultGrid();
        renderAttachmentsStrip();
        scheduleSave();
      });
      grid.appendChild(card);
    });

    if (state.mediaNotSaved) {
      const note = document.createElement("div");
      note.style.cssText = "grid-column:1/-1;font-size:12px;color:var(--slip);font-weight:600";
      note.textContent =
        "These attachments are too big for this browser's storage, so they won't survive a reload. Use Server Sync → Download .bellobook.json to keep them.";
      grid.appendChild(note);
    }
  }

  function bindVaultAndAudioEvents() {
    // New Folder button
    document.getElementById("newFolderBtn").addEventListener("click", () => {
      const name = window.prompt("New folder path (use / for nested subfolders):", "Ship's Log/Harbor");
      if (name && name.trim()) {
        const clean = name.trim().replace(/^\/+|\/+$/g, "");
        if (!state.customFolders.includes(clean)) state.customFolders.push(clean);
        state.activeFolder = clean;
        renderAll();
      }
    });

    // Export Markdown (.md)
    document.getElementById("exportMarkdownBtn").addEventListener("click", () => {
      const nb = getActiveNotebook();
      let md = `# ${nb.title}\n\n`;
      if (nb.folderPath) md += `*Folder:* \`${nb.folderPath}\`\n\n`;
      nb.lines.filter((l) => l.trim().length > 0).forEach((l) => {
        md += `${l}\n\n`;
      });
      if (nb.attachments && nb.attachments.length > 0) {
        md += `## Attachments\n`;
        nb.attachments.forEach((a) => {
          md += `- [${a.kind.toUpperCase()}] ${a.title} (${a.filename})\n`;
        });
      }
      downloadTextFile(md, `${nb.title.replace(/[^a-z0-9]+/gi, "_") || "BelloBook"}.md`, "text/markdown");
    });

    // Export PDF (Browser Print-to-PDF)
    document.getElementById("exportPdfBtn").addEventListener("click", () => {
      window.print();
    });

    // Media Vault Modal
    document.getElementById("openVaultBtn").addEventListener("click", () => {
      document.getElementById("vaultPreviewPane").style.display = "none";
      renderVaultGrid();
      els.vaultModal.classList.add("open");
    });
    document.getElementById("closeVaultBtn").addEventListener("click", () => {
      els.vaultModal.classList.remove("open");
    });
    document.getElementById("closeVaultPreviewBtn").addEventListener("click", () => {
      document.getElementById("vaultPreviewPane").style.display = "none";
    });

    document.getElementById("vaultFileInput").addEventListener("change", (e) => {
      const files = Array.from(e.target.files || []);
      const nb = getActiveNotebook();
      if (!nb.attachments) nb.attachments = [];
      files.forEach((file) => {
        const kind = file.type.startsWith("image/")
          ? "image"
          : file.type.startsWith("audio/")
          ? "audio"
          : file.type.startsWith("video/")
          ? "video"
          : "file";
        const reader = new FileReader();
        reader.onload = () => {
          const att = {
            id: "att-" + Date.now() + "-" + Math.random().toString(36).slice(2, 6),
            kind,
            filename: file.name,
            title: file.name.replace(/\.[^.]+$/, ""),
            artist: kind === "audio" ? "Local Track" : "",
            album: "",
            mimeType: file.type || "application/octet-stream",
            dataUrl: typeof reader.result === "string" ? reader.result : null,
            textPreview: null
          };
          if (kind === "file" && (file.type.startsWith("text/") || /\.(md|txt|csv|json)$/i.test(file.name))) {
            file.text().then((txt) => {
              att.textPreview = txt;
              nb.attachments.push(att);
              saveLibrary();
              renderVaultGrid();
              renderAttachmentsStrip();
            });
          } else {
            nb.attachments.push(att);
            saveLibrary();
            renderVaultGrid();
            renderAttachmentsStrip();
          }
        };
        reader.readAsDataURL(file);
      });
      e.target.value = "";
    });

    document.getElementById("addDemoAudioBtn").addEventListener("click", () => {
      const nb = getActiveNotebook();
      if (!nb.attachments) nb.attachments = [];
      const demo = {
        id: "att-demo-" + Date.now(),
        kind: "audio",
        filename: "sea-breeze-chime.wav",
        title: "Harbor Focus Chime",
        artist: "BelloBook Audio Deck",
        album: "Ship's Log Sessions",
        mimeType: "audio/wav",
        isDemoSynth: true
      };
      nb.attachments.push(demo);
      renderVaultGrid();
      renderAttachmentsStrip();
      scheduleSave();
      playAudioAttachment(demo);
    });

    // Audio Deck Controls
    document.getElementById("audioPlayPauseBtn").addEventListener("click", () => {
      if (htmlAudio) {
        if (state.audioPlaying) {
          htmlAudio.pause();
          state.audioPlaying = false;
        } else {
          htmlAudio.play().catch(() => {});
          state.audioPlaying = true;
        }
        renderAudioDeckBar();
      } else if (state.audioIndex >= 0) {
        startCurrentAudioTrack();
      }
    });
    document.getElementById("audioNextBtn").addEventListener("click", () => {
      if (state.audioQueue.length === 0) return;
      state.audioIndex = (state.audioIndex + 1) % state.audioQueue.length;
      startCurrentAudioTrack();
    });
    document.getElementById("audioPrevBtn").addEventListener("click", () => {
      if (state.audioQueue.length === 0) return;
      state.audioIndex = (state.audioIndex - 1 + state.audioQueue.length) % state.audioQueue.length;
      startCurrentAudioTrack();
    });
    document.getElementById("audioCloseBtn").addEventListener("click", () => {
      stopRawAudio();
      state.audioPlaying = false;
      state.audioIndex = -1;
      renderAudioDeckBar();
    });

    // One-Server Sync Modal
    const syncInput = document.getElementById("syncServerUrlInput");
    const syncStatus = document.getElementById("syncStatusMsg");
    document.getElementById("openSyncModalBtn").addEventListener("click", () => {
      syncInput.value = state.syncServerUrl || "http://localhost:8080";
      syncStatus.textContent = state.syncServerUrl
        ? `Server: ${state.syncServerUrl}`
        : "Local-only: your notes are saved in this browser.";
      els.syncModal.classList.add("open");
    });
    document.getElementById("closeSyncBtn").addEventListener("click", () => {
      els.syncModal.classList.remove("open");
    });
    const ARCHIVE_NAME = "BelloBook-Library.bellobook.json";
    const archiveUrl = (base) => `${base.replace(/\/+$/, "")}/${ARCHIVE_NAME}`;

    function rememberServer() {
      const url = syncInput.value.trim();
      state.syncServerUrl = url;
      try {
        localStorage.setItem("bellobook.syncUrl", url);
      } catch (_) {}
      return url;
    }

    function restoreLibrary(text, source) {
      let data = null;
      try {
        data = JSON.parse(text);
      } catch (_) {}
      const count = applyLibrary(data, true);
      if (count === 0) {
        syncStatus.textContent = `${source} isn't a BelloBook library (.bellobook.json).`;
        return;
      }
      // Rows are reused between renders, so rebuild them for the restored notebook.
      els.workLinesContainer.innerHTML = "";
      renderAll();
      syncStatus.textContent = `✓ Restored ${count} ${count === 1 ? "notebook" : "notebooks"} from ${source}.`;
    }

    // Upload: PUT the whole library as one file, the same way the iPad app uploads to a server.
    document.getElementById("saveSyncBtn").addEventListener("click", async () => {
      const url = rememberServer();
      if (!url) {
        syncStatus.textContent = "Cleared server URL (local-only mode).";
        return;
      }
      syncStatus.textContent = `Uploading to ${url}…`;
      try {
        const res = await fetch(archiveUrl(url), {
          method: "PUT",
          headers: { "Content-Type": "application/json" },
          body: libraryJSON(true, false)
        });
        syncStatus.textContent = res.ok
          ? `✓ Uploaded ${state.notebooks.length} notebooks to ${archiveUrl(url)}.`
          : `The server answered ${res.status}, so nothing was uploaded.`;
      } catch (_) {
        syncStatus.textContent = `Couldn't reach ${url}, so nothing was uploaded. Your notes are still saved in this browser.`;
      }
    });

    document.getElementById("fetchSyncBtn").addEventListener("click", async () => {
      const url = rememberServer();
      if (!url) {
        syncStatus.textContent = "Enter your server's address first.";
        return;
      }
      syncStatus.textContent = `Fetching from ${url}…`;
      try {
        const res = await fetch(archiveUrl(url), { cache: "no-store" });
        if (!res.ok) {
          syncStatus.textContent = `The server answered ${res.status}: no library found at ${archiveUrl(url)}.`;
          return;
        }
        restoreLibrary(await res.text(), url);
      } catch (_) {
        syncStatus.textContent = `Couldn't reach ${url}.`;
      }
    });

    document.getElementById("exportArchiveJsonBtn").addEventListener("click", () => {
      downloadTextFile(libraryJSON(true, true), ARCHIVE_NAME, "application/json");
    });

    document.getElementById("importArchiveInput").addEventListener("change", async (e) => {
      const file = (e.target.files || [])[0];
      e.target.value = "";
      if (file) restoreLibrary(await file.text(), file.name);
    });
  }

  function downloadTextFile(content, filename, mimeType) {
    const blob = new Blob([content], { type: mimeType });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  }

  // ============================================================================
  // 9. Anki SM-2, Obsidian Textbook / Wiki-Links & Computer LaTeX Rendering
  // ============================================================================
  function renderLaTeXHTML(expr, displayMode = false) {
    if (typeof window !== "undefined" && window.katex && typeof window.katex.renderToString === "function") {
      try {
        return window.katex.renderToString(expr, { displayMode, throwOnError: false });
      } catch (_) {}
    }
    // Offline fallback formatter. Groups are rewritten innermost-first, so nested ones such as
    // \frac{-b \pm \sqrt{b^{2} - 4ac}}{2a} come out readable too.
    let nested = escapeHTML(expr);
    for (let pass = 0; pass < 8; pass++) {
      const before = nested;
      nested = nested
        .replace(/\\frac\{([^{}]*)\}\{([^{}]*)\}/g, "($1)/($2)")
        .replace(/\\sqrt\{([^{}]*)\}/g, "√($1)")
        .replace(/\^\{([^{}]*)\}/g, "<sup>$1</sup>")
        .replace(/_\{([^{}]*)\}/g, "<sub>$1</sub>");
      if (nested === before) break;
    }
    const pretty = nested
      .replace(/\^([0-9a-zA-Z])/g, "<sup>$1</sup>")
      .replace(/\\pi/g, "π")
      .replace(/\\cdot/g, "·")
      .replace(/\\times/g, "×")
      .replace(/\\pm/g, "±")
      .replace(/\\neq/g, "≠")
      .replace(/\\sum/g, "∑")
      .replace(/\\int/g, "∫");
    return displayMode ? `<code>${pretty}</code>` : `<code style="font-family:serif">${pretty}</code>`;
  }

  function formatInlineMarkdownAndLaTeX(raw) {
    // Extract $$...$$ and $...$ before escaping HTML
    const mathTokens = [];
    let tokenized = raw.replace(/\$\$([^$]+)\$\$/g, (_, expr) => {
      const idx = mathTokens.length;
      mathTokens.push(renderLaTeXHTML(expr.trim(), true));
      return `@@MATH_${idx}@@`;
    });
    tokenized = tokenized.replace(/\$([^$]+)\$/g, (_, expr) => {
      const idx = mathTokens.length;
      mathTokens.push(renderLaTeXHTML(expr.trim(), false));
      return `@@MATH_${idx}@@`;
    });

    let html = escapeHTML(tokenized);
    // [[Wiki-Links]]
    html = html.replace(/\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g, (_, target, label) => {
      const disp = label || target;
      return `<button class="wiki-link-pill" data-wikilink="${escapeAttr(target.trim())}">[[${disp}]]</button>`;
    });
    // ==highlight==
    html = html.replace(/==([^=]+)==/g, '<mark class="obsidian-mark">$1</mark>');
    // **bold**, *italic*, `code`
    // Emphasis has to hug its text (*word*), so "2 * 3 * 4" stays multiplication.
    html = html.replace(/\*\*(?!\s)([^*]+?)(?<!\s)\*\*/g, "<strong>$1</strong>");
    html = html.replace(/\*(?!\s)([^*]+?)(?<!\s)\*/g, "<em>$1</em>");
    html = html.replace(/`([^`]+)`/g, "<code>$1</code>");
    // #tags
    html = html.replace(/(^|\s)#([A-Za-z][A-Za-z0-9_/-]*)/g, '$1<span class="obsidian-tag">#$2</span>');
    // Restore LaTeX HTML
    html = html.replace(/@@MATH_(\d+)@@/g, (_, idx) => mathTokens[Number(idx)] || "");
    return html;
  }

  function renderTextbookPreviewIfActive() {
    if (!els.textbookPreview || !els.workLinesContainer) return;
    const toggleBtn = document.getElementById("toggleTextbookBtn");
    if (toggleBtn) toggleBtn.classList.toggle("btn-pill-active", state.textbookMode);

    if (!state.textbookMode) {
      els.textbookPreview.style.display = "none";
      els.workLinesContainer.style.display = "flex";
      return;
    }

    els.workLinesContainer.style.display = "none";
    els.textbookPreview.style.display = "flex";

    const nb = getActiveNotebook();
    const lines = nb.lines;
    const out = [];
    let i = 0;

    while (i < lines.length) {
      const t = lines[i].trim();
      if (!t) {
        i++;
        continue;
      }
      if (t.startsWith("$$") && t.endsWith("$$") && t.length > 4) {
        const inner = t.slice(2, -2).trim();
        out.push(`<div class="latex-display-box">${renderLaTeXHTML(inner, true)}</div>`);
        i++;
        continue;
      }
      if (t.startsWith("> [!")) {
        const closeIdx = t.indexOf("]");
        if (closeIdx > 4) {
          const kind = t.slice(4, closeIdx).toLowerCase();
          const title = t.slice(closeIdx + 1).trim() || kind.toUpperCase();
          const bodyLines = [];
          i++;
          while (i < lines.length && lines[i].trim().startsWith(">")) {
            bodyLines.push(lines[i].trim().slice(1).trim());
            i++;
          }
          const bodyHtml = bodyLines.map(formatInlineMarkdownAndLaTeX).join("<br>");
          out.push(
            `<div class="textbook-callout callout-${escapeAttr(kind)}">` +
              `<div class="textbook-callout-title">${escapeHTML(title)}</div>` +
              `<div>${bodyHtml}</div>` +
            `</div>`
          );
          continue;
        }
      }
      if (t.startsWith("# ")) {
        out.push(`<div class="textbook-h1">${formatInlineMarkdownAndLaTeX(t.slice(2))}</div>`);
      } else if (t.startsWith("## ")) {
        out.push(`<div class="textbook-h2">${formatInlineMarkdownAndLaTeX(t.slice(3))}</div>`);
      } else {
        out.push(`<div style="font-size:15px;line-height:1.6">${formatInlineMarkdownAndLaTeX(t)}</div>`);
      }
      i++;
    }

    // Incoming Obsidian Backlinks
    const backlinks = state.notebooks.filter((other) => {
      if (other.id === nb.id) return false;
      const joined = other.lines.join("\n").toLowerCase();
      return joined.includes(`[[${nb.title.toLowerCase()}]]`);
    });
    if (backlinks.length > 0) {
      out.push(
        `<div style="margin-top:16px;padding-top:12px;border-top:1px solid var(--hairline)">` +
          `<div class="sidebar-section-title">Obsidian Backlinks (${backlinks.length})</div>` +
          `<div style="display:flex;gap:8px;flex-wrap:wrap">` +
            backlinks.map((b) => `<button class="wiki-link-pill" data-wikilink="${escapeAttr(b.title)}">← [[${escapeHTML(b.title)}]]</button>`).join("") +
          `</div>` +
        `</div>`
      );
    }

    els.textbookPreview.innerHTML = out.length > 0 ? out.join("") : `<div style="color:var(--muted)">Write Markdown, Obsidian callouts, or LaTeX ($...$) to preview.</div>`;
    els.textbookPreview.querySelectorAll("[data-wikilink]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const targetTitle = btn.getAttribute("data-wikilink");
        openOrCreateWikiLink(targetTitle);
      });
    });
  }

  function openOrCreateWikiLink(title) {
    const found = state.notebooks.find((n) => n.title.toLowerCase() === title.toLowerCase());
    if (found) {
      state.activeNotebookId = found.id;
      state.activeLineIndex = 0;
      renderAll();
      return;
    }
    const id = "nb-" + Date.now();
    state.notebooks.unshift({
      id,
      title,
      subtitle: "Created via [[Wiki-Link]]",
      folderPath: getActiveNotebook().folderPath || "Ship's Log",
      coverColor: "#0A60FF",
      paperStyle: "ruled",
      lines: [`# ${title}`, `Linked from [[${getActiveNotebook().title}]]`, ""],
      strokes: [],
      attachments: []
    });
    state.activeNotebookId = id;
    state.activeLineIndex = 2;
    renderAll();
  }

  function bindAnkiAndObsidianEvents() {
    // Textbook View toggle
    document.getElementById("toggleTextbookBtn").addEventListener("click", () => {
      state.textbookMode = !state.textbookMode;
      renderPaperSheet();
    });

    // Computer LaTeX & Obsidian Keyboard Quick-Insert Bar
    document.querySelectorAll("[data-insert]").forEach((chip) => {
      chip.addEventListener("click", () => {
        const snippet = chip.getAttribute("data-insert");
        const nb = getActiveNotebook();
        if (state.textbookMode) {
          state.textbookMode = false;
        }
        const idx = Math.max(0, Math.min(nb.lines.length - 1, state.activeLineIndex));
        const cur = nb.lines[idx] || "";
        nb.lines[idx] = cur ? `${cur} ${snippet}` : snippet;
        renderPaperSheet();
        refreshLineInputs();
        renderFollowerDock();
        const inputs = els.workLinesContainer.querySelectorAll(".work-line-input");
        if (inputs[idx]) inputs[idx].focus();
      });
    });

    // Anki Modal
    const openAnkiBtn = document.getElementById("openAnkiBtn");
    const closeAnkiBtn = document.getElementById("closeAnkiBtn");
    const ankiFlipBtn = document.getElementById("ankiFlipBtn");
    const ankiStage = document.getElementById("ankiCardStage");
    const ankiRateGrid = document.getElementById("ankiRateGrid");
    const ankiStatusMsg = document.getElementById("ankiStatusMsg");

    function formatAnkiCloze(text, reveal) {
      // The text reaching here has already been HTML-escaped, so it is used as is.
      return text.replace(/\{\{c\d+::([^:}]+)(?:::([^}]+))?\}\}/g, (_, ans, hint) => {
        if (reveal) return `<strong style="color:var(--verified)">${ans}</strong>`;
        return `<span style="color:var(--accent);font-weight:700">[${hint || "…"}]</span>`;
      });
    }

    function sm2Next(card, grade) {
      let { ease, interval, reps } = card;
      if (grade === 1) {
        reps = 0;
        interval = 0;
      } else {
        reps += 1;
        if (reps === 1) interval = grade === 4 ? 4 : 1;
        else if (reps === 2) interval = grade === 4 ? 7 : grade === 2 ? 3 : 6;
        else interval = Math.max(interval + 1, Math.round(interval * ease * (grade === 4 ? 1.3 : grade === 2 ? 0.85 : 1)));
      }
      ease = Math.max(1.3, ease + (0.1 - (4 - grade) * (0.08 + (4 - grade) * 0.02)));
      return { ease, interval, reps };
    }

    function renderAnkiModal() {
      scheduleSave();
      const now = Date.now();
      const dueCards = state.ankiCards.filter((c) => c.due <= now);
      document.getElementById("ankiQueueCount").textContent = dueCards.length;

      if (dueCards.length === 0) {
        ankiStage.innerHTML = `<div style="font-weight:700;color:var(--verified)">✓ All due Anki cards reviewed!</div><div style="font-size:12px;color:var(--muted)">Add new cards on the right or import from your notebook.</div>`;
        ankiRateGrid.style.display = "none";
      } else {
        const card = dueCards[state.ankiIndex % dueCards.length];
        const frontHtml = formatInlineMarkdownAndLaTeX(card.front).replace(/\{\{c\d+::[^}]+\}\}/g, (m) => formatAnkiCloze(m, state.ankiFlipped));
        const backHtml = card.back ? formatInlineMarkdownAndLaTeX(card.back) : "";
        ankiStage.innerHTML = `
          <div style="font-size:16px;line-height:1.5">${frontHtml}</div>
          ${state.ankiFlipped && backHtml ? `<hr style="width:60%;border:none;border-top:1px solid var(--hairline)"><div style="font-size:15px;color:var(--ink)">${backHtml}</div>` : ""}
        `;
        ankiRateGrid.style.display = state.ankiFlipped ? "grid" : "none";
        document.getElementById("ankiInt1").textContent = "1m";
        document.getElementById("ankiInt2").textContent = `${Math.max(1, sm2Next(card, 2).interval)}d`;
        document.getElementById("ankiInt3").textContent = `${Math.max(1, sm2Next(card, 3).interval)}d`;
        document.getElementById("ankiInt4").textContent = `${Math.max(1, sm2Next(card, 4).interval)}d`;
      }

      const listEl = document.getElementById("ankiCardList");
      listEl.innerHTML = "";
      state.ankiCards.forEach((c) => {
        const row = document.createElement("div");
        row.className = "step-log-item";
        row.innerHTML = `<span style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${escapeHTML(c.front)}</span><span style="font-size:10px;color:var(--muted)">${c.interval ? c.interval + "d" : "New"}</span>`;
        listEl.appendChild(row);
      });
    }

    openAnkiBtn.addEventListener("click", () => {
      state.ankiFlipped = false;
      ankiStatusMsg.textContent = "";
      renderAnkiModal();
      els.ankiModal.classList.add("open");
    });
    closeAnkiBtn.addEventListener("click", () => els.ankiModal.classList.remove("open"));
    ankiFlipBtn.addEventListener("click", () => {
      state.ankiFlipped = !state.ankiFlipped;
      renderAnkiModal();
    });

    document.querySelectorAll("[data-anki-rate]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const grade = Number(btn.getAttribute("data-anki-rate"));
        const now = Date.now();
        const dueCards = state.ankiCards.filter((c) => c.due <= now);
        if (dueCards.length === 0) return;
        const card = dueCards[state.ankiIndex % dueCards.length];
        const next = sm2Next(card, grade);
        card.ease = next.ease;
        card.interval = next.interval;
        card.reps = next.reps;
        card.due = grade === 1 ? now + 60_000 : now + next.interval * 86_400_000;
        state.ankiFlipped = false;
        renderAnkiModal();
      });
    });

    document.getElementById("ankiAddCardBtn").addEventListener("click", () => {
      const f = document.getElementById("ankiNewFront").value.trim();
      const b = document.getElementById("ankiNewBack").value.trim();
      if (!f) return;
      state.ankiCards.unshift({ id: "card-" + Date.now(), front: f, back: b, ease: 2.5, interval: 0, reps: 0, due: 0 });
      document.getElementById("ankiNewFront").value = "";
      document.getElementById("ankiNewBack").value = "";
      renderAnkiModal();
    });

    document.getElementById("ankiFromNoteBtn").addEventListener("click", () => {
      const nb = getActiveNotebook();
      let added = 0;
      let skipped = 0;
      // Lines the Work Checker flags are left out: a card must not teach a wrong answer.
      WorkChecker.checkLines(nb.lines, -1).forEach(({ text, feedback }) => {
        const line = text.trim();
        const eq = line.indexOf("=");
        if (line.length <= 3 || eq <= 0 || eq === line.length - 1) return;
        if (feedback.kind === "needsAttention") {
          skipped++;
          return;
        }
        const front = `${line.slice(0, eq).trim()} = ?`;
        const back = line.slice(eq + 1).trim();
        if (state.ankiCards.some((c) => c.front === front && c.back === back)) return;
        state.ankiCards.unshift({ id: "card-" + Date.now() + Math.random(), front, back, ease: 2.5, interval: 0, reps: 0, due: 0 });
        added++;
      });
      const skippedNote = skipped > 0 ? ` Skipped ${skipped} ${skipped === 1 ? "line" : "lines"} the Work Checker flagged.` : "";
      ankiStatusMsg.textContent =
        added > 0
          ? `✓ Created ${added} Anki ${added === 1 ? "card" : "cards"} from "${nb.title}".${skippedNote}`
          : `No new cards: write equations (a = b) on the page to auto-generate cards.${skippedNote}`;
      renderAnkiModal();
    });

    document.getElementById("exportAnkiTxtBtn").addEventListener("click", () => {
      const rows = ["#separator:tab", "#html:false", "#deck:BelloBook", ...state.ankiCards.map((c) => `${c.front.replace(/\t/g, " ")}\t${c.back.replace(/\t/g, " ")}`)];
      downloadTextFile(rows.join("\n"), "BelloBook-Anki.txt", "text/plain");
      ankiStatusMsg.textContent = "✓ Exported Anki-ready .txt (File → Import in Anki).";
    });

    document.getElementById("pushAnkiConnectBtn").addEventListener("click", async () => {
      ankiStatusMsg.textContent = "Connecting to AnkiConnect (127.0.0.1:8765)…";
      // AnkiConnect answers {result, error}; a 200 response can still carry an error.
      const ankiConnect = async (action, params) => {
        const res = await fetch("http://127.0.0.1:8765", {
          method: "POST",
          body: JSON.stringify({ action, version: 6, params })
        });
        const reply = await res.json();
        if (reply && reply.error) throw new Error(String(reply.error));
        return reply ? reply.result : null;
      };
      let connected = false;
      try {
        await ankiConnect("createDeck", { deck: "BelloBook" });
        connected = true;
        const notes = state.ankiCards.map((c) => ({
          deckName: "BelloBook",
          modelName: "Basic",
          fields: { Front: c.front, Back: c.back || c.front },
          tags: ["bellobook"],
          options: { allowDuplicate: false }
        }));
        // addNotes fails as a whole if any note can't be added (already in Anki, say), so ask first.
        const allowed = await ankiConnect("canAddNotes", { notes });
        const fresh = notes.filter((_, i) => Array.isArray(allowed) && allowed[i]);
        if (fresh.length > 0) await ankiConnect("addNotes", { notes: fresh });
        const already = notes.length - fresh.length;
        ankiStatusMsg.textContent =
          `✓ Added ${fresh.length} ${fresh.length === 1 ? "card" : "cards"} to desktop Anki` +
          (already > 0 ? ` (${already} already there).` : ".");
      } catch (err) {
        ankiStatusMsg.textContent = connected
          ? `Anki refused the cards: ${err.message}`
          : "AnkiConnect not detected on localhost:8765 (use Export Anki .txt anytime).";
      }
    });

    // Obsidian Sync Modal
    const openObsidianBtn = document.getElementById("openObsidianBtn");
    const closeObsidianBtn = document.getElementById("closeObsidianBtn");
    const obsStatus = document.getElementById("obsidianSyncStatus");

    openObsidianBtn.addEventListener("click", () => {
      obsStatus.textContent = "";
      els.obsidianModal.classList.add("open");
    });
    closeObsidianBtn.addEventListener("click", () => els.obsidianModal.classList.remove("open"));

    // YAML double-quoted scalar: backslashes and quotes escaped, kept on one line.
    const yamlString = (value) => `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\s*\r?\n\s*/g, " ")}"`;
    const noteFileName = (title) => `${title.replace(/[/\\?%*:|"<>]/g, "-").trim() || "Untitled"}.md`;

    function notebookToMarkdown(nb) {
      const lines = nb.lines.slice();
      while (lines.length > 0 && !lines[lines.length - 1].trim()) lines.pop();
      return `---\ntitle: ${yamlString(nb.title)}\nfolder: ${yamlString(nb.folderPath || "")}\nbellobook_id: ${yamlString(nb.id)}\n---\n\n# ${nb.title}\n\n${lines.join("\n")}\n`;
    }

    // Reads a note back: the frontmatter BelloBook wrote (title, folder, id) is lifted out and the
    // "# Title" heading it added is dropped, so exporting and importing again doesn't pile up headers.
    function markdownToNotebook(text, fileName) {
      let body = text.replace(/^\uFEFF/, "");
      const meta = {};
      const front = body.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
      if (front) {
        body = body.slice(front[0].length);
        front[1].split(/\r?\n/).forEach((row) => {
          const m = row.match(/^([A-Za-z_][\w-]*):\s*(.*)$/);
          if (!m) return;
          let value = m[2].trim();
          if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
            value = value.slice(1, -1).replace(/\\(["\\])/g, "$1");
          }
          meta[m[1]] = value;
        });
      }
      const title = meta.title || fileName.replace(/\.(md|markdown)$/i, "");
      const lines = body.split(/\r?\n/);
      while (lines.length > 0 && !lines[0].trim()) lines.shift();
      if (lines.length > 0 && lines[0].trim() === `# ${title}`) {
        lines.shift();
        while (lines.length > 0 && !lines[0].trim()) lines.shift();
      }
      return { id: meta.bellobook_id || null, title, folderPath: meta.folder != null ? meta.folder : "Obsidian", lines };
    }

    // Adds a note from Obsidian, or refreshes the notebook it was exported from. Returns "new",
    // "updated" or "same".
    function importMarkdown(text, fileName) {
      const note = markdownToNotebook(text, fileName);
      const existing = note.id ? state.notebooks.find((n) => n.id === note.id) : null;
      if (existing) {
        const current = existing.lines.slice();
        while (current.length > 0 && !current[current.length - 1].trim()) current.pop();
        if (existing.title === note.title && current.join("\n") === note.lines.join("\n").replace(/\n+$/, "")) return "same";
        existing.title = note.title;
        existing.lines = note.lines;
        return "updated";
      }
      state.notebooks.unshift({
        id: "nb-" + Date.now() + "-" + Math.random().toString(36).slice(2, 8),
        title: note.title,
        subtitle: "Imported from Obsidian",
        folderPath: note.folderPath,
        coverColor: "#6B4EFF",
        paperStyle: "ruled",
        lines: note.lines,
        strokes: [],
        attachments: []
      });
      return "new";
    }

    document.getElementById("syncObsidianFolderBtn").addEventListener("click", async () => {
      if (typeof window.showDirectoryPicker !== "function") {
        obsStatus.textContent = "Folder picker requires Chrome/Edge/Arc — use Import .md Files or Download Markdown below.";
        return;
      }
      try {
        const dirHandle = await window.showDirectoryPicker({ mode: "readwrite" });

        // 1. Read the vault's notes first, so edits made in Obsidian aren't overwritten below.
        let added = 0;
        let updated = 0;
        for await (const entry of dirHandle.values()) {
          if (entry.kind !== "file" || !/\.(md|markdown)$/i.test(entry.name)) continue;
          const outcome = importMarkdown(await (await entry.getFile()).text(), entry.name);
          if (outcome === "new") added++;
          else if (outcome === "updated") updated++;
        }

        // 2. Write every notebook out. Two notebooks with the same title get distinct file names.
        let written = 0;
        const usedNames = new Set();
        for (const nb of state.notebooks) {
          let name = noteFileName(nb.title);
          for (let n = 2; usedNames.has(name.toLowerCase()); n++) name = noteFileName(`${nb.title} ${n}`);
          usedNames.add(name.toLowerCase());
          const fileHandle = await dirHandle.getFileHandle(name, { create: true });
          const writable = await fileHandle.createWritable();
          await writable.write(notebookToMarkdown(nb));
          await writable.close();
          written++;
        }
        els.workLinesContainer.innerHTML = "";
        renderAll();
        obsStatus.textContent =
          `✓ Synced with "${dirHandle.name}": wrote ${written} notes` +
          (added + updated > 0 ? `, read ${added} new and ${updated} changed from the vault.` : ".");
      } catch (err) {
        if (err && err.name !== "AbortError") obsStatus.textContent = `Obsidian sync failed: ${err.message || err.name}.`;
      }
    });

    document.getElementById("obsidianImportFilesInput").addEventListener("change", async (e) => {
      const files = Array.from(e.target.files || []);
      e.target.value = "";
      let added = 0;
      let updated = 0;
      for (const file of files) {
        const outcome = importMarkdown(await file.text(), file.name);
        if (outcome === "new") added++;
        else if (outcome === "updated") updated++;
      }
      if (files.length > 0) {
        if (added > 0) state.activeNotebookId = state.notebooks[0].id;
        state.activeLineIndex = 0;
        els.workLinesContainer.innerHTML = "";
        renderAll();
        obsStatus.textContent = `✓ Imported ${added} new and updated ${updated} of ${files.length} Markdown ${files.length === 1 ? "note" : "notes"}.`;
      }
    });

    document.getElementById("obsidianDownloadBundleBtn").addEventListener("click", () => {
      const nb = getActiveNotebook();
      downloadTextFile(notebookToMarkdown(nb), noteFileName(nb.title), "text/markdown");
      obsStatus.textContent = `✓ Downloaded "${noteFileName(nb.title)}" with Obsidian YAML frontmatter.`;
    });
  }

  function escapeHTML(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function escapeAttr(str) {
    return escapeHTML(str).replace(/'/g, "&#39;");
  }

  document.addEventListener("DOMContentLoaded", initDOM);
})();


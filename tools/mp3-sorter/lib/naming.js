// Shared naming/sorting helpers. UMD-style so it works in both the Electron
// main process (require) and the renderer (loaded via <script>, attaches to window).
(function (root, factory) {
  if (typeof module === "object" && module.exports) {
    module.exports = factory();
  } else {
    root.naming = factory();
  }
})(typeof self !== "undefined" ? self : this, function () {
  const BANK_SIZE = 24; // sound keys A..X per bank
  const NUM_BANKS = 6; // 6 banks -> 144 tracks
  const TOTAL_SLOTS = BANK_SIZE * NUM_BANKS;
  const PREFIX_RE = /^(\d{4})_(.*)$/;

  // Returns { num: 1-based int | null, rest: name without the NNNN_ prefix }.
  function parsePrefix(filename) {
    const m = filename.match(PREFIX_RE);
    if (m) return { num: parseInt(m[1], 10), rest: m[2] };
    return { num: null, rest: filename };
  }

  // Strip an existing NNNN_ prefix, keeping the descriptive part (and extension).
  function stripPrefix(filename) {
    return parsePrefix(filename).rest;
  }

  function pad4(n) {
    return String(n).padStart(4, "0");
  }

  // 1-based bank number for a 1-based slot (slot 1..24 -> bank 1, etc.).
  function bankOfSlot(slot) {
    return Math.floor((slot - 1) / BANK_SIZE) + 1;
  }

  // Track-number prefix for a 1-based slot: bank*100 + position-in-bank.
  //   slot 1   -> 101 (bank 1, key 1)   slot 24  -> 124
  //   slot 25  -> 201                    slot 144 -> 624
  function prefixForSlot(slot) {
    const bank = bankOfSlot(slot);
    const pos = ((slot - 1) % BANK_SIZE) + 1;
    return bank * 100 + pos;
  }

  // Inverse of prefixForSlot: a prefix number back to a 1-based slot, or null
  // if it is not a valid bank*100 + position value.
  function slotFromPrefix(num) {
    const bank = Math.floor(num / 100);
    const pos = num % 100;
    if (bank < 1 || bank > NUM_BANKS || pos < 1 || pos > BANK_SIZE) return null;
    return (bank - 1) * BANK_SIZE + pos;
  }

  // Final on-disk name for a file placed at the given 1-based slot.
  function finalName(slot, originalName) {
    return `${pad4(prefixForSlot(slot))}_${stripPrefix(originalName)}`;
  }

  // Build the initial ordering for a set of filenames:
  //   - files with a valid NNNN_ prefix claim their slot number
  //   - files without a prefix are sorted alphabetically and fill the lowest
  //     remaining free slots
  // Returns an array of filenames in slot order (index 0 = slot 1), no gaps.
  function buildInitialOrder(filenames) {
    const prefixed = [];
    const plain = [];
    for (const name of filenames) {
      const { num } = parsePrefix(name);
      const slot = num === null ? null : slotFromPrefix(num);
      // Only bank*100+pos prefixes map to a slot; anything else sorts alphabetically.
      if (slot !== null) prefixed.push({ name, slot });
      else plain.push(name);
    }
    plain.sort((a, b) => a.localeCompare(b, undefined, { sensitivity: "base" }));

    // Place prefixed files at their slot; collisions bump to the next free slot.
    const bySlot = new Map();
    prefixed.sort((a, b) => a.slot - b.slot);
    for (const { name, slot: wanted } of prefixed) {
      let slot = wanted;
      while (bySlot.has(slot)) slot++;
      bySlot.set(slot, name);
    }
    // Fill plain files into the lowest free slots (alphabetical order).
    let cursor = 1;
    for (const name of plain) {
      while (bySlot.has(cursor)) cursor++;
      bySlot.set(cursor, name);
      cursor++;
    }
    // Flatten to a dense, gap-free array in slot order.
    const maxSlot = Math.max(0, ...bySlot.keys());
    const ordered = [];
    for (let s = 1; s <= maxSlot; s++) {
      if (bySlot.has(s)) ordered.push(bySlot.get(s));
    }
    return ordered;
  }

  return {
    BANK_SIZE,
    NUM_BANKS,
    TOTAL_SLOTS,
    parsePrefix,
    stripPrefix,
    pad4,
    finalName,
    bankOfSlot,
    prefixForSlot,
    slotFromPrefix,
    buildInitialOrder,
  };
});

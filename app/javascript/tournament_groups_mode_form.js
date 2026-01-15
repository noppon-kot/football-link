document.addEventListener("turbo:load", setupTournamentGroupsModeForm);
document.addEventListener("DOMContentLoaded", setupTournamentGroupsModeForm);

var __randomSlotDelegationBound = false;

function setupTournamentGroupsModeForm() {
  setupRandomSlotAssignments();

  var forms = document.querySelectorAll(".js-division-form");
  if (!forms.length) return;

  forms.forEach(function (form) {
    var totalTeams = parseInt(form.dataset.totalTeams || "0", 10);
    var modeInputs = form.querySelectorAll(".js-competition-mode");
    var groupCountInput = form.querySelector(".js-group-count");
    var slotsInput = form.querySelector(".js-slots-per-group");
    var matchFormatField = form.querySelector(".js-field-match-format");
    var groupCountField = form.querySelector(".js-field-group-count");
    var slotsField = form.querySelector(".js-field-slots-per-group");
    var knockoutSizeField = form.querySelector(".js-field-knockout-size");
    var thirdPlaceField = form.querySelector(".js-field-third-place");

    if (!modeInputs.length) return;

    function currentMode() {
      var checked = Array.prototype.find.call(modeInputs, function (el) { return el.checked; });
      return checked ? checked.value : "group_with_knockout";
    }

    function updateVisibility() {
      var mode = currentMode();

      if (mode === "group_with_knockout") {
        if (groupCountField) groupCountField.style.display = "";
        if (slotsField) slotsField.style.display = "";
        if (matchFormatField) matchFormatField.style.display = "";
        if (knockoutSizeField) knockoutSizeField.style.display = "";
        if (thirdPlaceField) thirdPlaceField.style.display = "";
      } else if (mode === "league_only") {
        if (groupCountField) groupCountField.style.display = "";
        if (slotsField) slotsField.style.display = "";
        if (matchFormatField) matchFormatField.style.display = "";
        if (knockoutSizeField) knockoutSizeField.style.display = "none";
        if (thirdPlaceField) thirdPlaceField.style.display = "none";

        if (groupCountInput) {
          groupCountInput.value = 1;
          groupCountInput.readOnly = true;
        }
        if (slotsInput) {
          slotsInput.value = totalTeams || 0;
          slotsInput.readOnly = true;
        }
      } else if (mode === "knockout_only") {
        if (groupCountField) groupCountField.style.display = "none";
        if (slotsField) slotsField.style.display = "none";
        if (matchFormatField) matchFormatField.style.display = "none";
        if (knockoutSizeField) knockoutSizeField.style.display = "none";
        if (thirdPlaceField) thirdPlaceField.style.display = "";
      }
    }

    function recomputeSlotsPerGroup() {
      if (!slotsInput || !groupCountInput) return;
      var mode = currentMode();
      if (mode !== "group_with_knockout") return;

      var groups = parseInt(groupCountInput.value || "0", 10);
      if (!groups || groups <= 0) return;
      if (!totalTeams || totalTeams <= 0) return;

      // ถ้ามีสายเดียว ให้จำนวนทีมต่อสายเท่ากับจำนวนทีมทั้งหมด
      if (groups === 1) {
        slotsInput.value = totalTeams;
        return;
      }

      // หลายสาย: ปัดจำนวนทีมขึ้นเป็นเลขคู่แล้วหารตามจำนวนสาย
      var n = totalTeams;
      if (n % 2 === 1) n += 1; // ปัดขึ้นเป็นเลขคู่ก่อน

      var base = Math.floor(n / groups);
      if (base < 2) base = 2;

      // จำนวนทีมต่อสายขั้นต่ำ (สายที่มีทีมน้อยที่สุด)
      slotsInput.value = base;
    }

    function onModeInteraction() {
      // reset readOnly flags when เปลี่ยนโหมด
      if (groupCountInput) groupCountInput.readOnly = false;
      if (slotsInput) slotsInput.readOnly = false;

      updateVisibility();
      recomputeSlotsPerGroup();
    }

    modeInputs.forEach(function (input) {
      input.addEventListener("change", onModeInteraction);
      input.addEventListener("click", onModeInteraction);
    });

    if (groupCountInput) {
      groupCountInput.addEventListener("input", function () {
        recomputeSlotsPerGroup();
      });
    }

    // initial state
    updateVisibility();
    recomputeSlotsPerGroup();
  });

}

function setupRandomSlotAssignments() {
  if (__randomSlotDelegationBound) return;
  __randomSlotDelegationBound = true;

  document.addEventListener("click", function (e) {
    var btn = e.target && e.target.closest ? e.target.closest(".js-random-assign") : null;
    if (!btn) return;

    var form = btn.closest("form.js-slot-assignment-form");
    if (!form) return;

    var selects = Array.prototype.slice.call(
      form.querySelectorAll('select[name^="slot_assignments["]')
    );
    if (!selects.length) return;

    // shuffle order of slots to avoid bias
    shuffleInPlace(selects);

    var used = new Set();

    selects.forEach(function (sel) {
      // gather candidate team ids available in this select (skip blank)
      var candidates = [];
      Array.prototype.forEach.call(sel.options, function (opt) {
        var v = (opt.value || "").trim();
        if (!v) return;
        if (used.has(v)) return;
        candidates.push(v);
      });

      if (!candidates.length) {
        sel.value = "";
        sel.dispatchEvent(new Event("change", { bubbles: true }));
        return;
      }

      var chosen = candidates[Math.floor(Math.random() * candidates.length)];
      used.add(chosen);
      sel.value = chosen;
      sel.dispatchEvent(new Event("change", { bubbles: true }));
    });
  });
}

function shuffleInPlace(arr) {
  for (var i = arr.length - 1; i > 0; i--) {
    var j = Math.floor(Math.random() * (i + 1));
    var tmp = arr[i];
    arr[i] = arr[j];
    arr[j] = tmp;
  }
  return arr;
}

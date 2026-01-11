document.addEventListener("turbo:load", setupTournamentGroupsModeForm);

function setupTournamentGroupsModeForm() {
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

    modeInputs.forEach(function (input) {
      input.addEventListener("change", function () {
        // reset readOnly flags when เปลี่ยนโหมด
        if (groupCountInput) groupCountInput.readOnly = false;
        if (slotsInput) slotsInput.readOnly = false;

        updateVisibility();
        recomputeSlotsPerGroup();
      });
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

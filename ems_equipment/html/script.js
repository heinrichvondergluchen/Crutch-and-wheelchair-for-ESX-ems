window.addEventListener('DOMContentLoaded', () => {
    const overlay = document.getElementById('overlay');
    const menuContainer = document.getElementById('menuContainer');
    const applyBtn = document.getElementById('applyBtn');
    const closeBtn = document.getElementById('closeBtn');
  
    applyBtn.addEventListener('click', () => {
      // Læs valg
      const equipmentValue = document.querySelector('input[name="equipmentType"]:checked').value;
      const playerSelect = document.getElementById('playerSelect');
      const durationSelect = document.getElementById('durationSelect');
  
      const chosenPlayerId = parseInt(playerSelect.value, 10);
      const chosenDuration = parseInt(durationSelect.value, 10);
  
      // Kald NUI Callback "chooseEquipment"
      fetch(`https://${GetParentResourceName()}/chooseEquipment`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          targetId: chosenPlayerId,
          duration: chosenDuration,
          equipmentType: equipmentValue
        })
      }).then(() => {
        // Skjul menu
        overlay.style.display = 'none';
        menuContainer.style.display = 'none';
      });
    });
  
    closeBtn.addEventListener('click', () => {
      fetch(`https://${GetParentResourceName()}/closeMenu`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
      }).then(() => {
        // Skjul
        overlay.style.display = 'none';
        menuContainer.style.display = 'none';
      });
    });
  });
  
  // Lyt efter messages fra client.lua => "open"
  window.addEventListener('message', (event) => {
    const data = event.data;
    if (data.action === 'open') {
      const overlay = document.getElementById('overlay');
      const menuContainer = document.getElementById('menuContainer');
      const playerSelect = document.getElementById('playerSelect');
      const durationSelect = document.getElementById('durationSelect');
  
      // Vis overlay og menu
      overlay.style.display = 'block';
      menuContainer.style.display = 'block';
  
      // Fyld spiller-listen
      playerSelect.innerHTML = '';
      (data.players || []).forEach((ply) => {
        const option = document.createElement('option');
        option.value = ply.id;
        option.textContent = `ID: ${ply.id} - ${ply.name}`;
        playerSelect.appendChild(option);
      });
  
      // Fyld durations 1-10
      durationSelect.innerHTML = '';
      for (let i = 1; i <= 10; i++) {
        const opt = document.createElement('option');
        opt.value = i;
        opt.textContent = `${i} minut(ter)`;
        durationSelect.appendChild(opt);
      }
  
      // Sæt radioknapper til standard "krykker"
      document.querySelector('input[name="equipmentType"][value="krykker"]').checked = true;
    }
  });
  
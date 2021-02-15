window.subscribeToCopy = (app) => {
  app.ports.copy.subscribe((s) => {
    console.log('copy', s);
    var e = document.createElement('input');
    e.value = s;
    document.body.appendChild(e);
    e.select();
    document.execCommand('copy');
    e.remove();
  });
};
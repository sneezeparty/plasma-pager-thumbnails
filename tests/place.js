// Lays out the test windows across both outputs and several desktops.
const d = workspace.desktops;
let konsoles = 0;
workspace.windowList().forEach(w => {
    if (!w.normalWindow) return;
    if (w.resourceClass == "org.kde.konsole") {
        if (konsoles++ == 0) { w.desktops = [d[0]]; w.frameGeometry = {x: 800, y: 350, width: 700, height: 450}; }   // main screen
        else { w.desktops = [d[2]]; w.frameGeometry = {x: 450, y: 420, width: 600, height: 400}; }                   // straddles both
    } else if (w.resourceClass == "org.kde.kwrite") { w.desktops = [d[1]]; w.frameGeometry = {x: 40, y: 200, width: 640, height: 700}; } // portrait
    else if (w.resourceClass == "org.kde.kcalc") { w.desktops = [d[1]]; w.frameGeometry = {x: 1300, y: 500, width: 400, height: 400}; }  // main screen
});

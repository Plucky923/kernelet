// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

(() => {
    const darkThemes = ['ayu', 'navy', 'coal'];
    const lightThemes = ['light', 'rust'];

    const classList = document.getElementsByTagName('html')[0].classList;

    let lastThemeWasLight = true;
    for (const cssClass of classList) {
        if (darkThemes.includes(cssClass)) {
            lastThemeWasLight = false;
            break;
        }
    }

    // Dark themes: Mermaid's `base` theme with the Kernelets palette (see kernelets.css), so the
    // design-chapter diagrams match the SVG figures on the Executive Summary. Light themes: Mermaid's default.
    const kernelets = {
        darkMode: true,
        background: '#060A24',
        fontFamily: '"IBM Plex Mono", ui-monospace, "SF Mono", Menlo, Consolas, monospace',
        fontSize: '13px',
        primaryColor: '#0F1E5A', primaryTextColor: '#E6F8FF', primaryBorderColor: '#00F7FF',
        secondaryColor: '#14172B', secondaryTextColor: '#C9CCE0', secondaryBorderColor: '#3A3F60',
        tertiaryColor: '#0B1030', tertiaryTextColor: '#9A9DB0', tertiaryBorderColor: '#2A2F52',
        mainBkg: '#0F1E5A', nodeBorder: '#00F7FF', nodeTextColor: '#E6F8FF',
        clusterBkg: '#0B1030', clusterBorder: '#3A3F60', titleColor: '#FFFFFF',
        lineColor: '#7FD8E0', textColor: '#C9CCE0', edgeLabelBackground: '#060A24',
        actorBkg: '#0F1E5A', actorBorder: '#00F7FF', actorTextColor: '#E6F8FF', actorLineColor: '#3A3F60',
        signalColor: '#C9CCE0', signalTextColor: '#C9CCE0',
        labelBoxBkgColor: '#0B1030', labelBoxBorderColor: '#3A3F60', labelTextColor: '#C9CCE0', loopTextColor: '#C9CCE0',
        noteBkgColor: '#14172B', noteBorderColor: '#3A3F60', noteTextColor: '#C9CCE0',
        activationBkgColor: '#1937FF', activationBorderColor: '#00F7FF', sequenceNumberColor: '#000319',
    };
    const config = lastThemeWasLight
        ? { startOnLoad: true, theme: 'default' }
        : { startOnLoad: true, theme: 'base', themeVariables: kernelets };
    mermaid.initialize(config);

    // Simplest way to make mermaid re-render the diagrams in the new theme is via refreshing the page

    // mdBook 0.5 names the theme buttons `mdbook-theme-<name>`; older versions used `<name>`.
    // (Patched relative to what `mdbook-mermaid install` writes; see README.md.)
    const themeButton = (name) => document.getElementById('mdbook-theme-' + name) || document.getElementById(name);

    for (const darkTheme of darkThemes) {
        themeButton(darkTheme)?.addEventListener('click', () => {
            if (lastThemeWasLight) {
                window.location.reload();
            }
        });
    }

    for (const lightTheme of lightThemes) {
        themeButton(lightTheme)?.addEventListener('click', () => {
            if (!lastThemeWasLight) {
                window.location.reload();
            }
        });
    }
})();

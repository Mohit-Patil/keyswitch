const root = document.documentElement;
const themeToggle = document.querySelector(".theme-toggle");
const demoCanvas = document.querySelector(".demo-canvas");

const preferredTheme = window.matchMedia("(prefers-color-scheme: light)").matches
  ? "light"
  : "dark";
const savedTheme = localStorage.getItem("keyswitch-theme");

function applyTheme(theme) {
  root.dataset.theme = theme;
  themeToggle?.setAttribute(
    "aria-label",
    theme === "dark" ? "Use light appearance" : "Use dark appearance",
  );
}

applyTheme(savedTheme ?? preferredTheme);

themeToggle?.addEventListener("click", () => {
  const nextTheme = root.dataset.theme === "dark" ? "light" : "dark";
  applyTheme(nextTheme);
  localStorage.setItem("keyswitch-theme", nextTheme);
});

document.querySelectorAll("[data-size]").forEach((button) => {
  if (!(button instanceof HTMLButtonElement)) return;
  button.addEventListener("click", () => {
    const size = button.dataset.size;
    if (!size || !demoCanvas) return;
    demoCanvas.dataset.size = size;
    document.querySelectorAll("[data-size]").forEach((candidate) => {
      candidate.classList.toggle("selected", candidate === button);
    });
  });
});

document.querySelectorAll("[data-preview-theme]").forEach((button) => {
  if (!(button instanceof HTMLButtonElement)) return;
  button.addEventListener("click", () => {
    const theme = button.dataset.previewTheme;
    if (!theme || !demoCanvas) return;
    demoCanvas.dataset.previewTheme = theme;
    document.querySelectorAll("[data-preview-theme]").forEach((candidate) => {
      candidate.classList.toggle("selected", candidate === button);
    });
  });
});

/*
  Beta sign-up.

  Set PROVIDER and ID below. See website/README.md for how to get the ID.
  Leave ID empty to run in preview mode: the form shows success but sends nothing.
*/
const CONFIG = {
  PROVIDER: "kit", // "kit" | "loops" | "buttondown"
  ID: "",          // Kit form ID, Loops form ID, or Buttondown username
};

const PROVIDERS = {
  // Kit (kit.com): free up to 10,000 subscribers.
  kit: (id, email) =>
    fetch(`https://app.kit.com/forms/${id}/subscriptions`, {
      method: "POST",
      headers: { Accept: "application/json" },
      body: new URLSearchParams({ email_address: email }),
    }).then(ok),

  // Loops (loops.so): free up to 1,000 contacts.
  loops: (id, email) =>
    fetch(`https://app.loops.so/api/newsletter-form/${id}`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ email, source: "beta-page" }),
    }).then(ok),

  // Buttondown (buttondown.com): free up to 100 subscribers.
  // Its embed endpoint doesn't send CORS headers, so the response can't be read.
  buttondown: (id, email) =>
    fetch(`https://buttondown.com/api/emails/embed-subscribe/${id}`, {
      method: "POST",
      mode: "no-cors",
      body: new URLSearchParams({ email, tag: "beta" }),
    }),
};

function ok(response) {
  if (!response.ok) throw new Error(`Sign-up failed (${response.status})`);
  return response;
}

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function subscribe(email) {
  if (!CONFIG.ID) {
    console.warn("[beta] No provider ID set in main.js. Preview mode: nothing was sent.", email);
    return new Promise((resolve) => setTimeout(resolve, 400));
  }
  return PROVIDERS[CONFIG.PROVIDER](CONFIG.ID, email);
}

document.querySelectorAll("[data-signup]").forEach((form) => {
  const input = form.querySelector("input[type=email]");
  const button = form.querySelector("button");
  const status = form.querySelector("[data-status]");
  const defaultNote = status.textContent;

  const show = (text, kind) => {
    status.textContent = text;
    status.classList.toggle("is-error", kind === "error");
    status.classList.toggle("is-success", kind === "success");
  };

  input.addEventListener("input", () => {
    if (status.classList.contains("is-error")) show(defaultNote);
  });

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const email = input.value.trim();
    if (!EMAIL.test(email)) {
      show("Enter a valid email address.", "error");
      input.focus();
      return;
    }

    button.disabled = true;
    try {
      await subscribe(email);
      form.classList.add("is-done");
      show("You’re on the list. We’ll email you when the beta opens.", "success");
      // Mirror the success state on the other form on the page.
      document.querySelectorAll("[data-signup]").forEach((other) => {
        if (other === form) return;
        other.classList.add("is-done");
        const note = other.querySelector("[data-status]");
        note.textContent = "You’re on the list.";
        note.classList.add("is-success");
      });
    } catch (error) {
      console.error(error);
      show("Something went wrong. Please try again.", "error");
    } finally {
      button.disabled = false;
    }
  });
});

document.querySelectorAll("[data-year]").forEach((el) => {
  el.textContent = new Date().getFullYear();
});

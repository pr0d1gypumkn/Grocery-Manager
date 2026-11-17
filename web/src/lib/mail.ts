/** Sends the sign-in code. Returns false when no provider is configured (dev: code is echoed). */
export async function sendCodeEmail(email: string, code: string): Promise<boolean> {
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) {
    console.log(`[mail] sign-in code for ${email}: ${code}`);
    return false;
  }
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: process.env.MAIL_FROM ?? "Mealy <no-reply@example.com>",
      to: [email],
      subject: `${code} is your Mealy sign-in code`,
      text: `Your sign-in code is ${code}. It expires in 10 minutes.`,
    }),
  });
  return response.ok;
}

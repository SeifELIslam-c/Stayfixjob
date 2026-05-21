require("dotenv").config();

const express = require("express");
const cors = require("cors");
const admin = require("firebase-admin");
const { getAuth } = require("firebase-admin/auth");
const { Resend } = require("resend");

const app = express();

app.use(
  cors({
    origin: process.env.ALLOWED_ORIGIN || "*",
  }),
);
app.use(express.json());

function requiredEnvMissing() {
  const required = [
    "RESEND_API_KEY",
    "EMAIL_FROM",
    "FIREBASE_PROJECT_ID",
    "FIREBASE_CLIENT_EMAIL",
    "FIREBASE_PRIVATE_KEY",
  ];

  return required.some((key) => !process.env[key]);
}

if (requiredEnvMissing()) {
  console.warn(
    "Missing one or more required environment variables. Password reset API will return a server configuration error until fixed.",
  );
}

const resend = new Resend(process.env.RESEND_API_KEY || "");

if (!admin.apps.length && !requiredEnvMissing()) {
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: process.env.FIREBASE_PROJECT_ID,
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
      privateKey: process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, "\n"),
    }),
  });
}

function getPasswordResetActionCodeSettings() {
  const continueUrl =
    process.env.PASSWORD_RESET_CONTINUE_URL ||
    `https://${process.env.FIREBASE_PROJECT_ID}.firebaseapp.com`;

  return {
    url: continueUrl,
    handleCodeInApp: false,
  };
}

function passwordResetEmailHtml(resetLink, email) {
  return `
  <div style="margin:0;padding:0;background:#f4f7fb;font-family:Arial,Helvetica,sans-serif;color:#111827;">
    <div style="max-width:620px;margin:0 auto;padding:24px 12px;">
      <div style="background:#ffffff;border-radius:24px;overflow:hidden;border:1px solid #e5e7eb;box-shadow:0 18px 45px rgba(15,23,42,0.10);">
        
        <img 
          src="https://ik.imagekit.io/1eyh6gcwx/email.webp" 
          alt="StayFix Job - Réinitialisation du mot de passe"
          style="width:100%;display:block;border:0;outline:none;text-decoration:none;"
        />

        <div style="padding:34px 30px 36px;">
          <p style="margin:0 0 10px;color:#2563EB;font-size:13px;font-weight:800;letter-spacing:0.12em;text-transform:uppercase;">
            Sécurité du compte
          </p>

          <h1 style="margin:0 0 16px;color:#0f172a;font-size:30px;line-height:1.22;font-weight:900;">
            Réinitialisation du mot de passe
          </h1>

          <p style="margin:0 0 24px;color:#475569;font-size:16px;line-height:1.7;">
            Bonjour,<br>
            Nous avons reçu une demande de réinitialisation du mot de passe pour votre compte
            <strong>StayFix Job</strong>.
          </p>

          <div style="text-align:center;margin:30px 0;">
            <a 
              href="${resetLink}" 
              target="_blank"
              style="display:inline-block;background:#2563EB;color:#ffffff;text-decoration:none;font-size:16px;font-weight:800;padding:16px 34px;border-radius:999px;box-shadow:0 12px 28px rgba(37,99,235,0.28);"
            >
              Réinitialiser mon mot de passe
            </a>
          </div>

          <div style="background:#f8fafc;border:1px solid #e5e7eb;border-radius:18px;padding:18px;margin:0 0 24px;">
            <p style="margin:0;color:#64748b;font-size:14px;line-height:1.7;">
              Si vous n’avez pas demandé cette réinitialisation, vous pouvez ignorer cet email en toute sécurité.
              Votre mot de passe ne sera pas modifié.
            </p>
          </div>

          <p style="margin:0 0 10px;color:#64748b;font-size:14px;line-height:1.6;">
            Si le bouton ne fonctionne pas, copiez et collez ce lien dans votre navigateur :
          </p>

          <p style="margin:0 0 26px;word-break:break-all;color:#2563EB;font-size:13px;line-height:1.6;">
            <a href="${resetLink}" target="_blank" style="color:#2563EB;text-decoration:none;">
              ${resetLink}
            </a>
          </p>

          <p style="margin:0;color:#0f172a;font-size:15px;line-height:1.7;">
            Merci,<br>
            <strong>L’équipe StayFix Job</strong>
          </p>
        </div>
      </div>

      <p style="margin:18px 0 0;text-align:center;color:#94a3b8;font-size:12px;line-height:1.6;">
        Cet email a été envoyé à ${email}.
      </p>
    </div>
  </div>
  `;
}

app.post("/api/password-reset", async (req, res) => {
  try {
    const { email } = req.body || {};

    if (!email || typeof email !== "string") {
      return res.status(400).json({
        success: false,
        message: "Email is required",
      });
    }

    if (requiredEnvMissing()) {
      return res.status(500).json({
        success: false,
        message: "Server configuration error",
      });
    }

    try {
      const resetLink = await getAuth().generatePasswordResetLink(
        email,
        getPasswordResetActionCodeSettings(),
      );

      await resend.emails.send({
        from: process.env.EMAIL_FROM,
        to: email,
        subject: "Réinitialisez votre mot de passe - StayFix Job",
        html: passwordResetEmailHtml(resetLink, email),
      });
    } catch (error) {
      console.error("Password reset internal error:", error);
    }

    return res.json({
      success: true,
      message: "Si ce compte existe, un email de réinitialisation a été envoyé.",
    });
  } catch (error) {
    console.error("Server error:", error);

    return res.status(500).json({
      success: false,
      message: "Server error",
    });
  }
});

const port = process.env.PORT || 3001;

app.listen(port, () => {
  console.log(`StayFix Job reset API running on port ${port}`);
});

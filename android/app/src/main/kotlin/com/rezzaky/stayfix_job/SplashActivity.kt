package com.rezzaky.stayfix_job

import android.app.Activity
import android.content.Intent
import android.os.Bundle

class SplashActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_splash)

        window.decorView.post {
            startActivity(Intent(this, MainActivity::class.java))
            finish()
            overridePendingTransition(0, 0)
        }
    }
}

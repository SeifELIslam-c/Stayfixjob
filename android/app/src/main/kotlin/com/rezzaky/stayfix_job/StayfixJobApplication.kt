package com.rezzaky.stayfix_job

import android.app.Application
import com.google.firebase.FirebaseApp

class StayfixJobApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        FirebaseApp.initializeApp(this)
    }
}

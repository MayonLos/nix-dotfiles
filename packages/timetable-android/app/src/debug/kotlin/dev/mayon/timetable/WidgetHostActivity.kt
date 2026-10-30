package dev.mayon.timetable

import android.app.Activity
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.os.Bundle
import android.widget.LinearLayout
import android.widget.TextView
import dev.mayon.timetable.widget.TodayWidgetReceiver
import dev.mayon.timetable.widget.NextWidgetReceiver

/** Debug-only system AppWidgetHost; displays real Glance RemoteViews for instrumentation evidence. */
class WidgetHostActivity : Activity() {
    private lateinit var host: AppWidgetHost
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        host = AppWidgetHost(this, 5050)
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(24, 60, 24, 24); setBackgroundColor(if (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK == android.content.res.Configuration.UI_MODE_NIGHT_YES) 0xff1e2228.toInt() else 0xfff5f6f7.toInt()) }
        val manager = AppWidgetManager.getInstance(this)
        listOf(TodayWidgetReceiver::class.java, NextWidgetReceiver::class.java).forEach { provider ->
            val id = host.allocateAppWidgetId()
            if (manager.bindAppWidgetIdIfAllowed(id, ComponentName(this, provider))) {
                val info = manager.getAppWidgetInfo(id)
                val view = host.createView(this, id, info)
                view.setAppWidget(id, info)
                layout.addView(view, LinearLayout.LayoutParams(-1, (if (provider == TodayWidgetReceiver::class.java) 300 else 180) * resources.displayMetrics.density.toInt()))
            } else layout.addView(TextView(this).apply { text = "需要模拟器授予 AppWidget 绑定权限"; setTextColor(-1) })
        }
        setContentView(layout)
    }
    override fun onStart() { super.onStart(); host.startListening() }
    override fun onStop() { host.stopListening(); super.onStop() }
    override fun onDestroy() { host.deleteHost(); super.onDestroy() }
}

package com.aurafinance.aura_finance

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Widget layar utama: pengeluaran hari ini + tombol catat cepat. */
class AuraWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.aura_widget).apply {
                setTextViewText(R.id.widget_today, widgetData.getString("today_expense", "Rp 0"))
                setTextViewText(R.id.widget_month, widgetData.getString("month_expense", "Bulan ini Rp 0"))
                val open = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                setOnClickPendingIntent(R.id.widget_root, open)
                val add = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("aura://add"))
                setOnClickPendingIntent(R.id.widget_add, add)
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

package com.rm.skifrei.android;

import android.app.Activity;
import android.app.Presentation;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.hardware.display.DisplayManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.Base64;
import android.util.Log;
import android.view.Display;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;

import com.godot.game.R;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Locale;

public final class SkifreiDuo extends GodotPlugin implements DisplayManager.DisplayListener {
    private static final String TAG = "SkifreiDuo";
    private static final int[] SPLASHES = {
        R.drawable.skifrei_duo_ski_jet,
        R.drawable.skifrei_duo_flag_jet_escape,
        R.drawable.skifrei_duo_tank_ambush,
        R.drawable.skifrei_duo_bomber_strike,
        R.drawable.skifrei_duo_turret_defence,
    };
    private final Handler ui = new Handler(Looper.getMainLooper());
    private DisplayManager displays;
    private Display lowerDisplay;
    private DuoPresentation panel;
    private int splashResource;
    private JSONObject data;
    private String arena;
    private Bitmap relief;
    private boolean resumed;
    private boolean openFailed;
    private boolean retriedDismissal;
    private volatile boolean available;

    public SkifreiDuo(Godot godot) {
        super(godot);
    }

    @Override public String getPluginName() {
        return TAG;
    }

    @Override public View onMainCreate(Activity activity) {
        if (isDuo()) {
            SharedPreferences preferences = activity.getSharedPreferences(TAG, Context.MODE_PRIVATE);
            int index = Math.floorMod(preferences.getInt("nextSplash", 0), SPLASHES.length);
            splashResource = SPLASHES[index];
            preferences.edit().putInt("nextSplash", (index + 1) % SPLASHES.length).apply();
            displays = activity.getSystemService(DisplayManager.class);
            if (displays != null) {
                displays.registerDisplayListener(this, ui);
                refreshDisplay();
            }
        }
        return null;
    }

    @Override public void onMainResume() {
        resumed = true;
        displayChanged();
    }

    @Override public void onMainPause() {
        resumed = false;
        closePanel();
    }

    @Override public void onMainDestroy() {
        if (displays != null) {
            displays.unregisterDisplayListener(this);
            displays = null;
        }
        available = false;
        lowerDisplay = null;
        closePanel();
        clearData();
    }

    @Override public void onDisplayAdded(int id) { displayChanged(); }
    @Override public void onDisplayChanged(int id) { displayChanged(); }
    @Override public void onDisplayRemoved(int id) { displayChanged(); }

    private void displayChanged() {
        retriedDismissal = false;
        refreshDisplay();
    }

    @UsedByGodot
    public boolean isDuo() {
        return Build.MODEL.toLowerCase(Locale.ROOT).startsWith("retroid pocket duo");
    }

    @UsedByGodot
    public boolean usesLetteredGamepad() {
        Activity host = getActivity();
        return isDuo() && host != null
                && Settings.System.getInt(host.getContentResolver(), "flip_button_layout", 0) == 0;
    }

    @UsedByGodot
    public boolean isAvailable() {
        return available;
    }

    @UsedByGodot
    public void setPanel(String json) {
        ui.post(() -> {
            if (displays == null) {
                return;
            }
            try {
                JSONObject next = new JSONObject(json);
                String type = next.optString("type");
                if (!type.equals("map") && !type.equals("results")) {
                    return;
                }
                if (type.equals("map")) {
                    readRelief(next);
                }
                data = next;
                showPanel();
            } catch (JSONException | IllegalArgumentException error) {
                Log.w(TAG, "Could not read the panel", error);
            }
        });
    }

    @UsedByGodot
    public void clearPanel() {
        ui.post(() -> {
            clearData();
            showPanel();
        });
    }

    private void clearData() {
        data = null;
        arena = null;
        relief = null;
        openFailed = false;
        retriedDismissal = false;
    }

    private void readRelief(JSONObject next) {
        String title = next.optString("title");
        if (!title.equals(arena)) {
            arena = title;
            relief = null;
        }
        // The terrain image is sent once per arena, even if the panel is recreated.
        String image = next.optString("relief");
        if (!image.isEmpty()) {
            byte[] bytes = Base64.decode(image, Base64.DEFAULT);
            relief = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
        }
    }

    private void refreshDisplay() {
        Display chosen = null;
        Activity host = getActivity();
        if (displays != null && host != null) {
            Display primary = Build.VERSION.SDK_INT >= 30 ? host.getDisplay() : null;
            int primaryId = primary == null ? Display.DEFAULT_DISPLAY : primary.getDisplayId();
            for (Display display : displays.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)) {
                int flags = display.getFlags();
                if (display.getDisplayId() != Display.DEFAULT_DISPLAY && display.getDisplayId() != primaryId
                        && display.isValid()
                        && display.getState() != Display.STATE_OFF && (flags & Display.FLAG_PRIVATE) == 0
                        && isBuiltIn(display)) {
                    chosen = display;
                    break;
                }
            }
        }
        if (panel != null && (chosen == null || chosen.getDisplayId() != panel.getDisplay().getDisplayId())) {
            closePanel();
        }
        lowerDisplay = chosen;
        available = chosen != null;
        openFailed = false;
        showPanel();
    }

    private static boolean isBuiltIn(Display display) {
        try {
            // Android hides the display type, but some firmware exposes it.
            return ((Integer) Display.class.getMethod("getType").invoke(display)) == 1;
        } catch (ReflectiveOperationException | SecurityException ignored) {
            return display.getName().startsWith("Built-in Screen");
        }
    }

    private void showPanel() {
        Activity host = getActivity();
        if (!resumed || lowerDisplay == null || host == null || openFailed) {
            return;
        }
        if (panel == null) {
            DuoPresentation next = new DuoPresentation(host, lowerDisplay, splashResource);
            next.setOnDismissListener(dialog -> {
                if (panel == next) {
                    panel = null;
                    // A new display mode can dismiss the old window after the display callback.
                    if (!retriedDismissal && resumed) {
                        retriedDismissal = true;
                        ui.post(this::refreshDisplay);
                    }
                }
            });
            try {
                next.show();
                panel = next;
                Log.i(TAG, "Opened bottom panel on display " + lowerDisplay.getDisplayId());
            } catch (WindowManager.InvalidDisplayException error) {
                openFailed = true;
                Log.w(TAG, "Could not open the bottom panel", error);
                return;
            }
        }
        panel.view.update(data, relief);
    }

    private void closePanel() {
        if (panel != null) {
            DuoPresentation previous = panel;
            panel = null;
            previous.dismiss();
        }
    }

    private static final class DuoPresentation extends Presentation {
        final PanelView view;

        DuoPresentation(Context host, Display display, int splashResource) {
            super(host, display, android.R.style.Theme_Material_NoActionBar);
            view = new PanelView(getContext(), splashResource);
            setContentView(view);
            setCancelable(false);
            Window window = getWindow();
            window.addFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                    | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                    | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN);
        }

        @Override protected void onStart() {
            super.onStart();
            Window window = getWindow();
            window.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT);
            if (Build.VERSION.SDK_INT >= 30) {
                window.setDecorFitsSystemWindows(false);
                WindowInsetsController insets = window.getInsetsController();
                if (insets != null) {
                    insets.hide(WindowInsets.Type.systemBars());
                }
            }
        }
    }

    private static final class PanelView extends View {
        private static final int INK = 0xff1a1410;
        private static final int CREAM = 0xfff3e6c8;
        private static final int AMBER = 0xfff3b06a;
        private static final int ORANGE = 0xffff8a3d;
        private static final int PINK = 0xffe0457b;
        private static final int PURPLE = 0xff6a2c91;
        private static final int LIME = 0xffa0ff40;
        private static final int BLUE = 0xff6fa0ff;
        private static final Typeface HEADING = Typeface.create("sans-serif-condensed", Typeface.BOLD);
        private static final Typeface BODY = Typeface.create("serif", Typeface.NORMAL);

        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
        private final RectF chart = new RectF();
        private final RectF labelBox = new RectF();
        private final ArrayList<RectF> occupied = new ArrayList<>();
        private final Path marker = new Path();
        private final RectF splashFrame = new RectF();
        private final int splashResource;
        private Bitmap splash;
        private JSONObject data;
        private Bitmap relief;

        PanelView(Context context, int splashResource) {
            super(context);
            this.splashResource = splashResource;
        }

        void update(JSONObject next, Bitmap image) {
            data = next;
            relief = image;
            invalidate();
        }

        @Override protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            canvas.drawColor(CREAM);
            float scale = Math.min(getWidth() / 640f, getHeight() / 480f);
            canvas.save();
            canvas.translate((getWidth() - 640 * scale) / 2, (getHeight() - 480 * scale) / 2);
            canvas.scale(scale, scale);
            if (data == null) {
                splash(canvas);
                canvas.restore();
                return;
            }
            boolean results = data.optString("type").equals("results");
            header(canvas, results);
            if (results) {
                results(canvas);
            } else {
                map(canvas);
            }
            canvas.restore();
        }

        private void splash(Canvas canvas) {
            if (splash == null) {
                BitmapFactory.Options options = new BitmapFactory.Options();
                options.inSampleSize = 2;
                splash = BitmapFactory.decodeResource(getResources(), splashResource, options);
            }
            float width = 408f * splash.getWidth() / splash.getHeight();
            splashFrame.set(320 - width / 2, 72, 320 + width / 2, 480);
            canvas.save();
            canvas.clipRect(0, 72, 640, 480);
            paint.setColor(0xffffffff);
            canvas.drawBitmap(splash, null, splashFrame, paint);
            canvas.restore();
            fill(canvas, INK, 0, 0, 640, 72);
            text(canvas, "SKIFREI", 18, 45, 38, CREAM, HEADING, Paint.Align.LEFT, 604);
            stripes(canvas, 62);
        }

        private void header(Canvas canvas, boolean results) {
            fill(canvas, INK, 0, 0, 640, 72);
            stripes(canvas, 62);
            String name = results ? "MATCH RESULTS" : data.optString("title").toUpperCase(Locale.ROOT);
            text(canvas, name, 18, 40, 29, CREAM, HEADING, Paint.Align.LEFT, 420);
            JSONArray scores = data.optJSONArray("scores");
            text(canvas, String.valueOf(number(scores, 0)), 458, 35, 26, LIME, HEADING, Paint.Align.CENTER, 52);
            text(canvas, String.valueOf(number(scores, 1)), 605, 35, 26, BLUE, HEADING, Paint.Align.CENTER, 52);
            int seconds = Math.max(0, data.optInt("seconds"));
            int winner = data.optInt("winner", -1);
            String middle = results ? (winner == -1 ? "DRAW" : (winner == 0 ? "LIME WINS" : "BLUE WINS"))
                    : String.format(Locale.ROOT, "%d:%02d", seconds / 60, seconds % 60);
            text(canvas, middle, 531, 34, 19, AMBER, HEADING, Paint.Align.CENTER, 92);
        }

        private void stripes(Canvas canvas, float top) {
            fill(canvas, ORANGE, 0, top, 640, top + 4);
            fill(canvas, PINK, 0, top + 4, 640, top + 7);
            fill(canvas, PURPLE, 0, top + 7, 640, top + 10);
        }

        private void map(Canvas canvas) {
            float aspect = (float) data.optDouble("aspect", 1.0);
            if (!Float.isFinite(aspect) || aspect <= 0) {
                aspect = 1;
            }
            float width = Math.min(584, 330 * aspect);
            float height = Math.min(330, 584 / aspect);
            chart.set(320 - width / 2, 252 - height / 2, 320 + width / 2, 252 + height / 2);
            paint.setColor(INK);
            canvas.drawRect(chart.left - 3, chart.top - 3, chart.right + 3, chart.bottom + 3, paint);
            canvas.save();
            canvas.clipRect(chart);
            paint.setColor(0xff826955);
            canvas.drawRect(chart, paint);
            if (relief != null) {
                paint.setColor(0xffffffff);
                canvas.drawBitmap(relief, null, chart, paint);
            }
            for (int i = 1; i < 6; i++) {
                paint.setColor(0x302a1911);
                float x = chart.left + i * chart.width() / 6;
                float y = chart.top + i * chart.height() / 6;
                canvas.drawLine(x, chart.top, x, chart.bottom, paint);
                canvas.drawLine(chart.left, y, chart.right, y, paint);
            }
            JSONArray markers = data.optJSONArray("markers");
            if (markers != null) {
                occupied.clear();
                JSONObject player = null;
                for (int i = 0; i < markers.length(); i++) {
                    JSONObject entry = markers.optJSONObject(i);
                    if (entry != null) {
                        mapMarker(canvas, entry);
                        if (entry.optString("kind").equals("you")) {
                            player = entry;
                        }
                    }
                }
                if (player != null) {
                    mapLabel(canvas, player);
                }
                for (int i = 0; i < markers.length(); i++) {
                    JSONObject entry = markers.optJSONObject(i);
                    if (entry != null && entry.optString("kind").equals("ally")) {
                        mapLabel(canvas, entry);
                    }
                }
            }
            canvas.restore();

            JSONArray powers = data.optJSONArray("powers");
            text(canvas, "LIME  " + power(powers, 0), 18, 451, 17, INK, HEADING, Paint.Align.LEFT, 160);
            text(canvas, "BLUE  " + power(powers, 1), 622, 451, 17, INK, HEADING, Paint.Align.RIGHT, 160);
            text(canvas, "Rings show sensor contacts", 320, 452, 15, INK, BODY, Paint.Align.CENTER, 300);
        }

        private void mapMarker(Canvas canvas, JSONObject entry) {
            float x = chart.left + (float) entry.optDouble("x", 0.5) * chart.width();
            float y = chart.top + (float) entry.optDouble("y", 0.5) * chart.height();
            occupied.add(new RectF(x - 10, y - 10, x + 10, y + 10));
            int team = teamColour(entry.optInt("team", -1));
            String kind = entry.optString("kind");
            switch (kind) {
                case "flag":
                    diamond(canvas, x, y, 10, INK);
                    diamond(canvas, x, y, 7, team);
                    break;
                case "hold":
                    fill(canvas, INK, x - 10, y - 10, x + 10, y + 10);
                    fill(canvas, team, x - 8, y - 8, x + 8, y + 8);
                    text(canvas, entry.optString("label"), x, y + 5, 13, INK, HEADING, Paint.Align.CENTER, 16);
                    return;
                case "contact":
                    circle(canvas, x, y, 6.5f, INK, true);
                    circle(canvas, x, y, 5, team, true);
                    return;
                case "waypoint":
                    diamond(canvas, x, y, 9, INK);
                    diamond(canvas, x, y, 6, AMBER);
                    break;
                case "call":
                    circle(canvas, x, y - 15, 10, INK, false);
                    circle(canvas, x, y - 15, 8, AMBER, false);
                    text(canvas, entry.optString("label"), x, y - 10, 13, INK, HEADING, Paint.Align.CENTER, 16);
                    return;
                case "you":
                    circle(canvas, x, y, 9, INK, false);
                    circle(canvas, x, y, 7, CREAM, false);
                    circle(canvas, x, y, 4, team, false);
                    break;
                default:
                    circle(canvas, x, y, 6, INK, false);
                    circle(canvas, x, y, 4.5f, team, false);
            }
        }

        private void mapLabel(Canvas canvas, JSONObject entry) {
            String label = entry.optString("label");
            if (label.isEmpty()) {
                return;
            }
            float x = chart.left + (float) entry.optDouble("x", 0.5) * chart.width();
            float y = chart.top + (float) entry.optDouble("y", 0.5) * chart.height();
            paint.setTypeface(HEADING);
            paint.setTextSize(12);
            float width = Math.min(95, paint.measureText(label));
            for (int corner = 0; corner < 4; corner++) {
                float left = (corner % 2 == 0) ? x + 13 : x - 13 - width;
                float baseline = corner < 2 ? y - 6 : y + 12;
                labelBox.set(left - 2, baseline - 12, left + width + 2, baseline + 3);
                if (!chart.contains(labelBox) || labelOverlaps()) {
                    continue;
                }
                occupied.add(new RectF(labelBox));
                paint.setStyle(Paint.Style.STROKE);
                paint.setStrokeWidth(2.5f);
                text(canvas, label, left, baseline, 12, INK, HEADING, Paint.Align.LEFT, 95);
                paint.setStyle(Paint.Style.FILL);
                text(canvas, label, left, baseline, 12, CREAM, HEADING, Paint.Align.LEFT, 95);
                return;
            }
        }

        private boolean labelOverlaps() {
            for (RectF box : occupied) {
                if (RectF.intersects(labelBox, box)) {
                    return true;
                }
            }
            return false;
        }

        private void results(Canvas canvas) {
            text(canvas, data.optString("title"), 320, 102, 20, INK, BODY, Paint.Align.CENTER, 602);
            JSONArray rows = data.optJSONArray("rows");
            boolean hold = data.optBoolean("hold");
            resultsTeam(canvas, 0, 16, rows, hold);
            resultsTeam(canvas, 1, 330, rows, hold);
        }

        private void resultsTeam(Canvas canvas, int team, float left, JSONArray rows, boolean hold) {
            int count = 0;
            if (rows != null) {
                for (int i = 0; i < rows.length(); i++) {
                    JSONObject row = rows.optJSONObject(i);
                    if (row != null && row.optInt("team", -1) == team) {
                        count++;
                    }
                }
            }
            fill(canvas, INK, left, 118, left + 294, 147);
            text(canvas, team == 0 ? "LIME" : "BLUE", left + 9, 140, 22, teamColour(team),
                    HEADING, Paint.Align.LEFT, 100);
            String[] columns = hold ? new String[]{"K", "A", "R"} : new String[]{"K", "G", "C", "R"};
            int[] indices = hold ? new int[]{0, 1, 6} : new int[]{0, 2, 3, 4};
            for (int col = 0; col < columns.length; col++) {
                text(canvas, columns[col], left + 181 + col * 30, 140, 15, CREAM,
                        HEADING, Paint.Align.CENTER, 28);
            }
            if (rows == null) {
                return;
            }
            float step = Math.min(29, 296f / Math.max(count, 1));
            int line = 0;
            for (int i = 0; i < rows.length(); i++) {
                JSONObject row = rows.optJSONObject(i);
                if (row == null || row.optInt("team", -1) != team) {
                    continue;
                }
                float top = 151 + line * step;
                float baseline = top + step * 0.75f;
                if (line % 2 == 0) {
                    fill(canvas, 0xffe8d7b6, left, top, left + 294, top + step);
                }
                float size = Math.min(19, step * 0.68f);
                text(canvas, row.optString("name"), left + 9, baseline, size, INK,
                        BODY, Paint.Align.LEFT, 149);
                JSONArray counts = row.optJSONArray("counts");
                for (int col = 0; col < indices.length; col++) {
                    text(canvas, String.valueOf(number(counts, indices[col])), left + 181 + col * 30,
                            baseline, size, INK, HEADING, Paint.Align.CENTER, 28);
                }
                line++;
            }
            String legend = hold ? "K kills   A assists   R repairs" : "K kills   G grabs   C captures   R returns";
            text(canvas, legend, left + 147, 462, 12, INK, BODY, Paint.Align.CENTER, 294);
        }

        private static String power(JSONArray powers, int team) {
            return powers != null && powers.optBoolean(team) ? "POWER ON" : "POWER DOWN";
        }

        private static int number(JSONArray values, int index) {
            return values == null ? 0 : values.optInt(index);
        }

        private static int teamColour(int team) {
            return team == 0 ? LIME : (team == 1 ? BLUE : AMBER);
        }

        private void text(Canvas canvas, String words, float x, float y, float size, int colour,
                          Typeface face, Paint.Align align, float width) {
            paint.setColor(colour);
            paint.setTypeface(face);
            paint.setTextAlign(align);
            paint.setTextSize(size);
            if (paint.measureText(words) > width) {
                int end = paint.breakText(words, true, width - paint.measureText("…"), null);
                words = words.substring(0, end) + "…";
            }
            canvas.drawText(words, x, y, paint);
        }

        private void diamond(Canvas canvas, float x, float y, float radius, int colour) {
            marker.reset();
            marker.moveTo(x, y - radius);
            marker.lineTo(x + radius, y);
            marker.lineTo(x, y + radius);
            marker.lineTo(x - radius, y);
            marker.close();
            paint.setColor(colour);
            canvas.drawPath(marker, paint);
        }

        private void circle(Canvas canvas, float x, float y, float radius, int colour, boolean outline) {
            paint.setColor(colour);
            paint.setStrokeWidth(2);
            paint.setStyle(outline ? Paint.Style.STROKE : Paint.Style.FILL);
            canvas.drawCircle(x, y, radius, paint);
            paint.setStyle(Paint.Style.FILL);
        }

        private void fill(Canvas canvas, int colour, float left, float top, float right, float bottom) {
            paint.setColor(colour);
            canvas.drawRect(left, top, right, bottom, paint);
        }
    }
}

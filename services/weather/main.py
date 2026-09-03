"""The weather, pinned, refreshed every fifteen minutes.

Every network call goes through cogiti, which checks it against the host in
service.toml. There is no socket in this file and there cannot be one: that is
what makes the manifest's allow-list true rather than decorative.
"""
import os

from cogiti.service import Service, every

svc = Service()

LAT = os.environ.get("WEATHER_LAT", "42.70")     # Sofia, by default
LON = os.environ.get("WEATHER_LON", "23.32")

CODES = {0: "clear", 1: "mostly clear", 2: "partly cloudy", 3: "overcast",
         45: "fog", 48: "fog", 51: "drizzle", 53: "drizzle", 55: "drizzle",
         61: "rain", 63: "rain", 65: "heavy rain", 71: "snow", 73: "snow",
         75: "heavy snow", 80: "showers", 81: "showers", 82: "showers",
         95: "thunderstorm"}


@every(900)
async def tick():
    data = await svc.get_json(
        "https://api.open-meteo.com/v1/forecast",
        params={"latitude": LAT, "longitude": LON, "current_weather": "true"})
    now = data["current_weather"]
    svc.show(kind="text", style="headline",
             text="%d°  %s" % (round(now["temperature"]),
                               CODES.get(now["weathercode"], "")))


svc.run()

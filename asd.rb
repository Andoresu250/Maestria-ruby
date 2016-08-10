require "http"

key = 'AIzaSyD2FUK8qUBrCBIZapK9VBpwjlXRA1XyuJw';

uri = "http://maps.googleapis.com/maps/api/distancematrix/json?origins=Barranquilla|Bogota&destinations=Barranquilla|Bogota&mode=driving&key=#{key}"

#asd = HTTP.get(uri).to_s
#print asd
asd = HTTP.get("https://github.com").to_s
print asd



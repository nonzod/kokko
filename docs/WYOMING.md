C'è una pipeline di pod collegati tra loro tramite protocollo whisper, questi sono integrati e configurati in homeassistant. In homeassistant riesco a fare TTS e a sentire il parlato nelle casse dell'host. nell'host ho  anche un microfono USB che dovrebbe venir usato da openwakeword, la word viene riconosciuta:

DEBUG:root:Connected to wake service
DEBUG:root:Streaming audio
e 
DEBUG:wyoming_openwakeword.handler:Detected okay_nabu at 10368 

però poi rimane in "straming" all'infinito e non fa nulla
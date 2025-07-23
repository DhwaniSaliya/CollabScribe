import 'dart:convert'; //for encoding the request body and decoding the response (jsonEncode, jsonDecode)
import 'package:flutter_dotenv/flutter_dotenv.dart'; //to load api key from .env file
import 'package:http/http.dart' as http; //to send post request to gemini API

class GeminiAPI {
  static final String? _apiKey = dotenv.env['GEMINI_API_KEY'];

  //this function sends the user’s prompt to Gemini and returns the AI’s response
  //It's static so it can be called without creating an instance: GeminiAPI.getAIResponse("your prompt")
  //otherwise hume object create karna padta and then hum obj.func ko call kar sakte thae
  static Future<String> getAIResponse(String prompt) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('GEMINI_API_KEY not found in .env file.');
    }

    //Gemini API endpoint for generating text using the Gemini 2.0 Flash model
    //obvoiusly api endpoint is a url provided that lets us send requests and get data
    //i got the endpoint from official doc of Gemini
    final String url =
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_apiKey';

    //structure of the request body
    final Map<String, dynamic> body = {
      "contents": [
        {
          "parts": [
            {"text": prompt}
          ]
        }
      ]
    };

    try {
      //sends post req: converts body to json str, adds proper headers, sends req to gemini api endpoint
      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );
      //let's understand...diff b/w get and post.
      //GET sends data in the URL, which has length limits and is visible in browser logs
      //POST sends data in the body, which is more secure, supports larger data, and is better for sensitive or dynamic input (like AI prompts)
      //if we want to hust view/read data - GET, if send data to server for processing(e.g. login, prompt, form) - POST

      if (response.statusCode == 200) {//handle success response
      //parse response body to dart map. tries to extract AI's reply text
        final data = jsonDecode(response.body);
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
        return text?.trim() ?? 'Gemini responded with no text.';
      } else {
        final errorBody = jsonDecode(response.body);
        final message = errorBody['error']?['message'] ?? 'Unknown error';
        print('[GeminiAPI] HTTP ${response.statusCode}: $message'); //Just logs the message to the console.
        throw Exception('[GeminiAPI] HTTP ${response.statusCode}: $message'); //Stops the function execution and throws an error
      }
    } catch (e) { //catches unexpected errors like json parsing errors etc
      print('[GeminiAPI] Exception: $e');
      return 'AI request failed: $e';
    }
  }
}

//https://ai.google.dev/api/generate-content#v1beta.GenerateContentResponse
//there we have something like this:
/*{
 "candidates": [
  {
  object (Candidate)
   }
 ],
 "promptFeedback": {
   object (PromptFeedback)
  },
  "usageMetadata": {
    object (UsageMetadata)
  },
  "modelVersion": string,
  "responseId": string
}*/
//on clicking on Candidate obj, we have inside:
/* {
    "content": {
    object (Content)
  },...
}*/
//on clicking Content, we have inside:
/*{
  "parts": [
    {
      object (Part)
    }
  ],..
}*/
//inside Part:
/*{
  "thought": boolean,
  "thoughtSignature": string,

  // data
  "text": string,
  "inlineData": {
    object (Blob)
  },
  "functionCall": {
    object (FunctionCall)
  },
*/

/* So our structure can be:
  final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
*/
//we use ? to avoid crashing if anything is null
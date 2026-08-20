"""
AI Provider - Connects to OpenAI or Google Gemini for AI-powered analysis.
Used by all agents (security, code review, deployment risk, log analysis).

Setup:
  - Set OPENAI_API_KEY or GEMINI_API_KEY as environment variable
  - Or pass as Harness secret: <+secrets.getValue("openai_api_key")>
"""

import os
import json
import urllib.request
import urllib.error


def get_ai_response(prompt, model="auto"):
    """
    Send prompt to AI provider and get response.
    Auto-detects which API key is available.
    
    Args:
        prompt: The analysis prompt to send
        model: "openai", "gemini", or "auto" (detect from env)
    
    Returns:
        AI response text
    """
    openai_key = os.environ.get("OPENAI_API_KEY", "")
    gemini_key = os.environ.get("GEMINI_API_KEY", "")

    # Auto-detect from AI_API_KEY (single secret — works for both providers)
    ai_key = os.environ.get("AI_API_KEY", "")
    if ai_key and not openai_key and not gemini_key:
        if ai_key.startswith("sk-"):
            openai_key = ai_key
        else:
            gemini_key = ai_key

    if model == "auto":
        if openai_key:
            model = "openai"
        elif gemini_key:
            model = "gemini"
        else:
            return "[ERROR] No AI API key found. Set OPENAI_API_KEY or GEMINI_API_KEY"

    if model == "openai":
        return _call_openai(prompt, openai_key)
    elif model == "gemini":
        return _call_gemini(prompt, gemini_key)
    else:
        return f"[ERROR] Unknown model: {model}"


def _call_openai(prompt, api_key):
    """Call OpenAI GPT-4o-mini API"""
    url = "https://api.openai.com/v1/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}"
    }
    data = json.dumps({
        "model": "gpt-4o-mini",
        "messages": [
            {"role": "system", "content": "You are a DevSecOps expert. Provide concise, actionable analysis."},
            {"role": "user", "content": prompt}
        ],
        "max_tokens": 2000,
        "temperature": 0.3
    }).encode("utf-8")

    try:
        req = urllib.request.Request(url, data=data, headers=headers)
        with urllib.request.urlopen(req, timeout=30) as response:
            result = json.loads(response.read().decode("utf-8"))
            return result["choices"][0]["message"]["content"]
    except urllib.error.HTTPError as e:
        return f"[ERROR] OpenAI API error: {e.code} - {e.read().decode()}"
    except Exception as e:
        return f"[ERROR] OpenAI request failed: {str(e)}"


def _call_gemini(prompt, api_key):
    """Call Google Gemini API"""
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key={api_key}"
    headers = {"Content-Type": "application/json"}
    data = json.dumps({
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "maxOutputTokens": 2000,
            "temperature": 0.3
        }
    }).encode("utf-8")

    try:
        req = urllib.request.Request(url, data=data, headers=headers)
        with urllib.request.urlopen(req, timeout=30) as response:
            result = json.loads(response.read().decode("utf-8"))
            return result["candidates"][0]["content"]["parts"][0]["text"]
    except urllib.error.HTTPError as e:
        return f"[ERROR] Gemini API error: {e.code} - {e.read().decode()}"
    except Exception as e:
        return f"[ERROR] Gemini request failed: {str(e)}"


if __name__ == "__main__":
    # Quick test
    response = get_ai_response("Say 'AI agent working!' in one line")
    print(response)

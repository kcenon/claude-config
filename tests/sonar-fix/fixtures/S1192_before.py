def has_admin(user):
    return user.role == "administrator"

def grant_admin(user):
    user.role = "administrator"
    save(user)

def is_admin_email(email):
    return email.endswith("@administrator.example.com") and "administrator" in email

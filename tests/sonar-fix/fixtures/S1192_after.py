ADMINISTRATOR_ROLE = "administrator"


def has_admin(user):
    return user.role == ADMINISTRATOR_ROLE

def grant_admin(user):
    user.role = ADMINISTRATOR_ROLE
    save(user)

def is_admin_email(email):
    return email.endswith("@administrator.example.com") and ADMINISTRATOR_ROLE in email

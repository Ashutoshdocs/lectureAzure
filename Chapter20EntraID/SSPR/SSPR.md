# 📘 Microsoft Entra ID – Self-Service Password Reset (SSPR)
## End-to-End UI-Based Practical | AZ-104

---

## 1. What is Self-Service Password Reset?

Self-Service Password Reset (SSPR) allows users to reset their forgotten Microsoft Entra ID passwords without contacting the IT administrator or helpdesk.

### Real-world scenario

Imagine an organization has 500 employees.

An employee forgets their Microsoft 365 password.

Traditionally:

1. Employee contacts the IT helpdesk.
2. Administrator verifies the employee's identity.
3. Administrator manually resets the password.
4. Employee receives the temporary password.
5. Employee signs in and changes the password.

With SSPR, the employee can verify their identity using registered authentication methods and reset the password independently.

### What we will implement

1. Create a Microsoft Entra security group.
2. Create a test user.
3. Assign the required license.
4. Enable SSPR for selected users.
5. Configure authentication methods.
6. Configure user registration.
7. Register security information.
8. Reset the password as an end user.
9. Verify the new password.
10. Explore SSPR monitoring and troubleshooting.

---

## 2. Architecture

```text
                 Microsoft Entra ID
                         |
                 Administrator
                         |
                 Create Security Group
                         |
                    GRP-USERS
                         |
                    User01 Added
                         |
                  Assign License
                         |
                  Enable SSPR
                         |
                 Authentication Policy
                         |
              +----------+----------+
              |                     |
          Email OTP             SMS OTP
              |                     |
              +----------+----------+
                         |
                 User Registration
                         |
                  User01 Registers
                   Security Info
                         |
                 User Forgets Password
                         |
                 https://aka.ms/sspr
                         |
                Verify User Identity
                         |
                  Enter New Password
                         |
                  Password Updated
```

---

# PART 1 – Create a Test User

## 3. Open Microsoft Entra Admin Center

Open:

https://entra.microsoft.com

Sign in using an administrator account.

Navigate:

```text
Microsoft Entra ID
       |
       +-- Users
              |
              +-- All users
```

### Create a new user

1. Click New user.
2. Select Create new user.
3. Enter the following details.

| Property | Value |
|---|---|
| User principal name | user01@yourdomain.com |
| Display name | User 01 |
| Password | Auto-generate |
| Account enabled | Yes |

4. Click Review + create.
5. Click Create.

<text> <escape> </escape> </text>

### Verify

Open the newly created user.

Check:

- User principal name
- Display name
- Account status
- Assigned licenses

Keep the initial password securely available for the demonstration.

---

# PART 2 – Create a Security Group

## 4. Create GRP-USERS

Navigate:

```text
Microsoft Entra ID
       |
       +-- Groups
              |
              +-- All groups
```

Click:

```text
+ New group
```

Configure:

| Property | Value |
|---|---|
| Group type | Security |
| Group name | GRP-USERS |
| Description | Users enabled for SSPR |
| Membership type | Assigned |
| Owners | Administrator |

Under Members:

1. Click No members selected.
2. Search for User 01.
3. Select the user.
4. Click Select.
5. Click Create.

### Verify group membership

Open:

```text
Groups
   |
   +-- GRP-USERS
          |
          +-- Members
```

Expected:

```text
GRP-USERS
    |
    +-- User 01
```

**Why do we create a group?**

Instead of enabling SSPR for the entire organization immediately, we can first enable it for a selected group and test the functionality.

---

# PART 3 – Assign Microsoft Entra License

## 5. Understand Licensing

SSPR licensing depends on the type of account and functionality.

For cloud-only user password reset, supported options include:

- Microsoft Entra ID P1.
- Microsoft Entra ID P2.
- Microsoft 365 Business Standard or higher eligible business plans.

For hybrid on-premises password writeback, additional licensing requirements apply.

For this lab, we will use Microsoft Entra ID P1.

Official documentation:

https://learn.microsoft.com/en-us/entra/identity/authentication/concept-sspr-licensing

## 6. Assign License to User 01

Open:

https://admin.microsoft.com

Navigate:

```text
Billing
   |
   +-- Licenses
```

Select Microsoft Entra ID P1.

Find the option to assign licenses.

Alternatively, use:

```text
Users
   |
   +-- Active users
          |
          +-- User 01
                 |
                 +-- Licenses and apps
```

1. Select User 01.
2. Open Licenses and apps.
3. Select Microsoft Entra ID P1.
4. Click Save changes.

### Verify

Return to:

```text
Microsoft Entra Admin Center
       |
       +-- Users
              |
              +-- User 01
                     |
                     +-- Licenses
```

Confirm that the license is assigned and active.

**Important:** Assign the appropriate license to every user who will benefit from SSPR.

---

# PART 4 – Enable Self-Service Password Reset

## 7. Open Password Reset

Open:

https://entra.microsoft.com

Navigate:

```text
Microsoft Entra ID
       |
       +-- Protection
              |
              +-- Password reset
```

Open the Properties page.

You will see:

**Self service password reset enabled**

Available options:

| Option | Meaning |
|---|---|
| None | SSPR disabled |
| Selected | Enable SSPR for selected group |
| All | Enable SSPR for all users |

### Configure SSPR for selected users

1. Select Selected.
2. Click No groups selected.
3. Search for GRP-USERS.
4. Select GRP-USERS.
5. Click Select.
6. Click Save.

<text>Expected configuration</text>

```text
Self service password reset enabled

              Selected

Selected group:
              GRP-USERS

              [ Save ]
```

### Verify

Return to Password reset → Properties.

Confirm:

```text
Status: Selected
Group: GRP-USERS
```

**Teaching point:** Only users included in the configured SSPR scope can use this password reset feature, subject to licensing and authentication requirements.

Microsoft currently supports selecting one group directly in the SSPR Properties configuration through the admin center. Nested groups are supported.

---

# PART 5 – Configure Authentication Methods

## 8. Why Are Authentication Methods Required?

Imagine an attacker knows the username of User 01.

If password reset only requires entering a username, the attacker could potentially impersonate that user.

To prevent this, Microsoft Entra ID requires users to verify their identity before resetting their passwords.

Examples:

- Microsoft Authenticator.
- Email verification code.
- Mobile phone SMS.
- Voice call.
- Other supported authentication methods.

**Important:** The available methods depend on the authentication policy and SSPR configuration. The user must have registered the required methods beforehand.

## 9. Configure Authentication Methods Policy

Microsoft has moved authentication-method management away from the legacy MFA and SSPR authentication-method policies.

Use the centralized Authentication methods policy.

Navigate:

```text
Microsoft Entra ID
       |
       +-- Authentication methods
              |
              +-- Policies
```

Open the relevant authentication method.

For this demonstration, configure the following methods where supported:

### Method 1 – Microsoft Authenticator

1. Select Microsoft Authenticator.
2. Enable the method.
3. Configure the target users or groups.
4. Save.

### Method 2 – SMS

1. Select SMS.
2. Enable the method.
3. Configure the target users or groups.
4. Save.

### Method 3 – Email OTP

Configure email verification if the method is available and supported for your scenario.

**Important:** The central Authentication methods policy controls the available authentication methods. You must also ensure that the methods are available and usable for SSPR.

## 10. Configure Number of Authentication Methods Required

Return to:

```text
Microsoft Entra ID
       |
       +-- Password reset
```

Open Authentication methods if the corresponding settings are available in your tenant.

Configure the number of authentication methods required for reset:

| Configuration | Meaning |
|---|---|
| 1 method | User verifies identity using one eligible method |
| 2 methods | User verifies identity using two eligible methods |

For classroom demonstration, use:

```text
Number of methods required to reset: 1
```

For a stronger security demonstration, configure two methods after ensuring that users have registered at least two eligible methods.

Save the configuration.

**Important:** Microsoft Authenticator and OATH methods have specific counting rules. Do not assume that two Authenticator registrations count as two independent methods.

---

# PART 6 – Configure User Registration

## 11. Enable User Registration

Users need to register their security information before attempting SSPR.

Navigate:

```text
Microsoft Entra ID
       |
       +-- Password reset
              |
              +-- Registration
```

Configure:

| Setting | Value |
|---|---|
| Require users to register when signing in | Yes |
| Number of days before users are asked to reconfirm their authentication information | 180 |

Click Save.

### What happens now?

When User 01 signs in, Microsoft Entra ID can prompt the user to register security information.

This could include:

- Mobile phone number.
- Email address.
- Microsoft Authenticator.

The user can also register manually using:

https://aka.ms/ssprsetup

**Teaching point:** Registration and password reset are two different processes.

Registration stores the authentication information.

Password reset uses that information to verify the user's identity.

---

# PART 7 – Configure Notifications

## 12. Enable Password Reset Notifications

Navigate:

```text
Microsoft Entra ID
       |
       +-- Password reset
              |
              +-- Notifications
```

Configure:

### Option 1 – Notify users on password resets

Set:

```text
Notify users on password resets: Yes
```

This sends a notification when the user's password is reset.

### Option 2 – Notify all admins when other admins reset their password

Set:

```text
Notify all admins when other admins reset their password: Yes
```

Save the configuration.

### Why are notifications important?

Suppose someone resets User 01's password without authorization.

The user receives a notification and can report suspicious activity to the IT department.

---

# PART 8 – Register Security Information as User 01

## 13. Sign in as User 01

Open an InPrivate or Incognito browser window.

Navigate:

https://aka.ms/ssprsetup

Sign in using:

```text
user01@yourdomain.com
```

Enter the initial password.

Complete any required first-time password change.

### Register authentication information

Depending on your configured methods:

1. Select Add sign-in method.
2. Add a mobile phone number.
3. Verify the phone using the OTP.
4. Add another eligible authentication method if required.
5. Complete the registration.

Expected:

```text
Security Info

    Phone
    +91 XXXXXXXXXX

    Microsoft Authenticator
    Registered
```

The actual options shown depend on your authentication-method policy.

### Verify registration

Navigate to:

https://mysignins.microsoft.com/security-info

Confirm that the required methods are registered.

---

# PART 9 – Perform the Actual Password Reset

## 14. Simulate a Forgotten Password

Now we will test the actual SSPR functionality.

Open an InPrivate or Incognito browser window.

Navigate:

https://aka.ms/sspr

Alternatively:

https://passwordreset.microsoftonline.com

Enter:

```text
user01@yourdomain.com
```

Enter the CAPTCHA if prompted.

Click Next.

## 15. Verify User Identity

Microsoft Entra ID will display the authentication methods available for User 01.

Example:

```text
Verify your identity

    Send a code to your registered email

    OR

    Send a text message to your registered mobile

    OR

    Approve using Microsoft Authenticator
```

Select an eligible authentication method.

Complete the verification process.

## 16. Enter a New Password

After successful verification:

1. Enter a new password.
2. Confirm the new password.
3. Click Finish.

Expected:

```text
Your password has been reset successfully.
```

### Verify the Password

Open another InPrivate browser session.

Navigate:

https://www.office.com

Sign in using:

```text
Username: user01@yourdomain.com
Password: New password
```

Expected:

<text color="success" weight="semibold">User successfully signs in using the new password.</text>

---

# PART 10 – Verify from Administrator Portal

## 17. Check SSPR Registration Activity

Sign in as an administrator.

Open:

https://entra.microsoft.com

Navigate to:

```text
Microsoft Entra ID
       |
       +-- Users
              |
              +-- User 01
```

Review the available authentication methods and user security information.

Also explore:

```text
Microsoft Entra ID
       |
       +-- Monitoring & health
              |
              +-- Audit logs
```

Filter for relevant password management and authentication registration activities.

You can also explore SSPR-specific reporting, where available in your tenant.

Review:

- User registration activity.
- Password reset activity.
- Authentication method registration.
- Failed password reset attempts.

---

# PART 11 – Test Different Scenarios

## 18. Scenario 1 – User Is Not Part of the Group

Create another user:

```text
user02@yourdomain.com
```

Do not add this user to GRP-USERS.

Attempt to reset the password.

Expected:

```text
SSPR is not enabled for this user.
```

The user may receive an error indicating that the administrator has not enabled the feature.

## 19. Scenario 2 – User Has Not Registered Security Information

Create:

```text
user03@yourdomain.com
```

Add the user to GRP-USERS and assign an appropriate license.

Do not register security information.

Attempt SSPR.

Expected:

```text
Additional security information is needed
to reset your password.
```

The administrator must help the user regain account access and complete registration.

## 20. Scenario 3 – User Has Registered Only One Method

Configure two authentication methods as required.

Ensure User 03 has registered only one eligible method.

Attempt SSPR.

Expected:

```text
Unable to complete password reset.
```

This demonstrates why users should register sufficient recovery methods.

## 21. Scenario 4 – Administrator Disables SSPR

Navigate:

```text
Microsoft Entra ID
       |
       +-- Password reset
              |
              +-- Properties
```

Change the configuration to:

```text
None
```

Save.

Attempt the password reset again.

Expected:

The user can no longer use SSPR.

For the next demonstration, restore Selected and select GRP-USERS.

---

# PART 12 – Troubleshooting

## 22. Common Problems

| Problem | Solution |
|---|---|
| Password reset option unavailable | Verify SSPR is enabled |
| User cannot access SSPR | Check group membership |
| License error | Assign an eligible license |
| Missing authentication methods | Review authentication-method policies |
| User cannot verify identity | Check registered security information |
| User cannot complete reset | Check required number of methods |
| Password rejected | Review password protection and password policy |
| Admin cannot see Password reset | Check administrator role and licensing |

### Useful URLs

| Purpose | URL |
|---|---|
| Entra Admin Center | https://entra.microsoft.com |
| Microsoft 365 Admin Center | https://admin.microsoft.com |
| SSPR Registration | https://aka.ms/ssprsetup |
| Password Reset | https://aka.ms/sspr |
| Security Information | https://mysignins.microsoft.com/security-info |

---

# PART 13 – AZ-104 Interview Questions

**Q1. What is Self-Service Password Reset?**

It allows users to reset their forgotten passwords without administrator intervention.

**Q2. Why do we create a security group for SSPR?**

To enable SSPR for selected users instead of the entire organization.

**Q3. What is the purpose of authentication methods?**

To verify the identity of the user before allowing password reset.

**Q4. What happens if a user is not part of the SSPR-enabled group?**

The user cannot use SSPR through that selected-group configuration.

**Q5. Why does a user need to register security information?**

Microsoft Entra ID needs a registered method to verify the user's identity.

**Q6. What is the difference between MFA and SSPR?**

MFA verifies identity during sign-in or other protected operations. SSPR uses identity verification to authorize password reset or account unlock.

**Q7. Can we enable SSPR for all users?**

Yes. Select All in the SSPR Properties configuration.

**Q8. What is the purpose of SSPR notifications?**

To notify users or administrators about password reset events.

**Q9. What is password writeback?**

It allows a password reset performed in Microsoft Entra ID to be written back to an on-premises Active Directory environment, when the required hybrid configuration and licensing are in place.

**Q10. Does SSPR work without a license?**

Cloud-only password reset requires an eligible license. Microsoft Entra ID Free supports cloud password change, but not the same cloud-only forgotten-password reset capability.

---

# PART 14 – Student Assignment

## 23. Complete This Practical

- [ ] Create User 01.
- [ ] Create GRP-USERS security group.
- [ ] Add User 01 to the group.
- [ ] Assign Microsoft Entra ID P1 or another eligible license.
- [ ] Enable SSPR for Selected users.
- [ ] Configure authentication methods.
- [ ] Configure registration settings.
- [ ] Configure notification settings.
- [ ] Register User 01 security information.
- [ ] Perform a password reset.
- [ ] Verify login using the new password.
- [ ] Create User 02 outside the group.
- [ ] Test that User 02 cannot use SSPR.
- [ ] Review audit logs.

---

# 24. Final Learning Outcome

After completing this practical, students should understand:

1. How to create users and security groups in Microsoft Entra ID.
2. How to assign Microsoft Entra licenses.
3. How to enable SSPR for selected users.
4. How authentication methods work.
5. How to register security information.
6. How end users reset forgotten passwords.
7. How to monitor SSPR activities.
8. How to troubleshoot common SSPR issues.

## Real-World Enterprise Use Case

An organization with 5,000 employees can enable SSPR for all eligible users.

Employees can independently recover their accounts using registered authentication methods.

This reduces helpdesk workload, improves employee productivity, and provides centralized identity management through Microsoft Entra ID.

---

# 25. Official Microsoft Documentation

1. Enable SSPR:
https://learn.microsoft.com/en-us/entra/identity/authentication/tutorial-enable-sspr

2. SSPR Licensing:
https://learn.microsoft.com/en-us/entra/identity/authentication/concept-sspr-licensing

3. SSPR How It Works:
https://learn.microsoft.com/en-us/entra/identity/authentication/concept-sspr-howitworks

4. Authentication Methods:
https://learn.microsoft.com/en-us/entra/identity/authentication/concept-authentication-methods

5. Troubleshooting:
https://learn.microsoft.com/en-us/entra/identity/authentication/troubleshoot-sspr
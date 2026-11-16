-- 0064: Africa's Talking STOP opt-out for DropOff SMS.
-- sendSms() consults this column for every non-transactional SMS.
-- Transactional SMS (OTP, payment codes, delivery status) is never blocked.
ALTER TABLE auth_users ADD COLUMN sms_opt_out INTEGER NOT NULL DEFAULT 0;

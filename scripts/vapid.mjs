import webpush from 'web-push';
// Explicit user-run setup tool; output is never embedded into source control.
console.log(webpush.generateVAPIDKeys());

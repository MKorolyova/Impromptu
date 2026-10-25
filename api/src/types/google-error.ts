// Error body returned by Google's OAuth and Calendar APIs.
export type GoogleErrorBody = {
  error:
    | string
    | {
        code: number;
        message: string;
        status?: string;
        errors?: { domain: string; reason: string; message: string }[];
      };
  error_description?: string;
};
